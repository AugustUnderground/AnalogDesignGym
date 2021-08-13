(import os)
(import sys)
(import [functools [partial]])

(import [torch :as pt])
(import [numpy :as np])
(import [pandas :as pd])

(import [skopt [gp-minimize]])

(import gym)
(import [gym.spaces [Dict Box Discrete Tuple]])

(import [.amp_env [*]])
(import [.prim_dev [*]])
(import [.util [*]])

(import jpype)
(import jpype.imports)
(import [jpype.types [*]])

(require [hy.contrib.walk [let]]) 
(require [hy.contrib.loop [loop]])
(require [hy.extra.anaphoric [*]])
(require [hy.contrib.sequences [defseq seq]])
(import [hy.contrib.sequences [Sequence end-sequence]])

;; THIS WILL BE FIXED IN HY 1.0!
;(import multiprocess)
;(multiprocess.set-executable (.replace sys.executable "hy" "python"))

(defclass SymAmpXH035Env [AmplifierEnv]
  """
  Derived amplifier class, implementing the Symmetrical Amplifier in the XFAB
  XH035 Technology. Only works in combinatoin with the right netlists.
  Observation Space:
    - See AmplifierEnv

  Action Space:
    Continuous Box a: (10,) ∈ [0;1]

    Where
    a = [ gmid-cm1 gmid-cm2 gmid-cm3 gmid-dp1 
          fug-cm1  fug-cm2  fug-cm3  fug-dp1 
          rcm1 rcm2 ] 

      rcm1 and rcm2 are the mirror ratios of the corresponding current mirrors.
  """

  (setv metadata {"render.modes" ["human" "ascii"]})

  (defn __init__ [self &optional ^str [nmos-path None]  ^str [pmos-path None] 
                                 ^str [lib-path None]   ^str [jar-path None]
                                 ^str [sim-path "/tmp"] ^str [ckt-path None]
                                 ^int [max-moves 200]   ^bool [close-target True]
                                 ^float [target-tolerance 1e-3] 
                                 ^dict [target None]]
    """
    Constructs a Symmetrical Amplifier Environment with XH035 device models and
    the corresponding netlist.
    Arguments:
      nmos-path:  Prefix path, expects to find `nmos-path/model.pt`, 
                  `nmos-path/scale.X` and `nmos-path/scale.Y` at this location.
      pmos-path:  Same as 'nmos-path', but for PMOS model.

      lib-path:   Path to XFAB MOS devices for XH035 pdk, something like 
                  /path/to/pdk/tech/xh035/cadence/vX_X/spectre/vX_X_X/mos
      jar-path:   Path to edlab.eda.characterization jar, something like
                  $HOME/.m2/repository/edlab/eda/characterization/$VERSION/characterization-$VERSION-jar-with-dependencies.jar
                  Has to be 'with-dependencies' otherwise waveforms can't be
                  loaded etc.
      sim-path:   Path to where the simulation results will be stored. Default
                  is /tmp.
      ckt-path:   Path where the amplifier netlist and testbenches are located.
      
      max-moves:  Maximum amount of steps the agent is allowed to take per
                  episode, before it counts as failed. Default = 200.
      
      close-target: If True (default), on each reset, a random target will be
                    chosen and by bayesian optimization, a location close to it
                    will be found for the starting point of the agent. This
                    increases the reset time significantly.
      target-tolerance: (| target - performance | <= tolerance) ? Success.
      target: Specific target, if given, no random targets will be generated,
              and the agent tries to find the same one over and over again.

    """

    (if-not (and lib-path jar-path ckt-path)
      (raise (TypeError f"SymAmpXH035Env requires 'lib_path', 'ckt-path' and 'jar-path' kwargs.")))

    ;; Launch JVM and import the Corresponding Amplifier Characterization Library
    ; f"/home/ynk/.m2/repository/edlab/eda/characterization/0.0.1/characterization-0.0.1-jar-with-dependencies.jar"
    (jpype.startJVM :classpath jar-path)
    (import [edlab.eda.characterization [Opamp2XH035Characterization]])
    
    ;; Load the PyTorch NMOS/PMOS Models for converting paramters.
    (setv self.nmos (PrimitiveDevice f"{nmos-path}/model.pt" 
                                     f"{nmos-path}/scale.X" 
                                     f"{nmos-path}/scale.Y")
          self.pmos (PrimitiveDevice f"{pmos-path}/model.pt" 
                                     f"{pmos-path}/scale.X" 
                                     f"{pmos-path}/scale.Y"))

    ;; Specify constants as they are defined in the netlist. 
    (setv self.vs   0.5
          self.cl   5e-12
          self.rl   100e6
          self.i0   3e-6
          self.vsup 3.3
          self.fin  1e3)

    ;; Initialize parent Environment.
    (.__init__ (super SymAmpXH035Env self) Opamp2XH035Characterization
                                           lib-path sim-path ckt-path 
                                           max-moves target-tolerance
                                           :close-target close-target)

    ;; Generate random target of None was provided.
    (setv self.same-target  (bool target)
          self.target       (or target (self.target-specification :noisy False)))

    ;; Specify geometric and electric parameters, these have to align with the
    ;; parameters defined in the netlist.
    (setv self.geometric-parameters [ "Lcm1" "Lcm2" "Lcm3" "Ld" 
                                      "Mcm11" "Mcm12" "Mcm21" "Mcm22" "Mcm31" "Mcm32" "Md"
                                      "Wcm1" "Wcm2" "Wcm3" "Wd" ]
          self.electric-parameters [ "gmid_cm1" "gmid_cm2" "gmid_cm3" "gmid_dp1" 
                                     "fug_cm1" "fug_cm2" "fug_cm3" "fug_dp1" ])

    ;; The action space consists of 10 parameters ∈ [0;1]. One gm/id and fug for
    ;; each building block. This is subject to change and will include branch
    ;; currents / mirror ratios in the future.
    (setv self.action-space (Box :low -1.0 :high 1.0 
                                 :shape (, 10) 
                                 :dtype np.float32)
          self.action-scale-min (np.array [7.0 7.0 7.0 7.0      ; gm/Id min
                                           1e6 5e5 1e6 1e6      ; fug min
                                           1.5 0.5])            ; Ratio min
          self.action-scale-max (np.array [17.0 17.0 17.0 17.0  ; gm/Id max
                                           1e9 5e8 1e9 1e9      ; fug max
                                           10.0 5.0]))          ; Ratio max

    ;; Loss function used for reward calculation. Either write your own, or
    ;; checkout util.Loss for more loss funtions provided with this package. 
    ;; Mean Absolute Percentage Error (MAPE)
    (setv self.loss Loss.MAPE))

  (defn step [self action]
    """
    Takes an array of electric parameters for each building block and 
    converts them to sizing parameters for each parameter specified in the
    netlist. This is passed to the parent class where the netlist ist modified
    and then simulated, returning observations, reward, done and info.

    TODO: Implement sizing procedure.
    """

    (let [(, gmid-cm1 gmid-cm2 gmid-cm3 gmid-dp1
             fug-cm1  fug-cm2  fug-cm3  fug-dp1 
             rcm1 rcm2 ) (unscale-value action self.action-scale-min 
                                               self.action-scale-max)
          
          (, Mcm11 Mcm12)    (dec2frac rcm1)
          (, Mcm21 Mcm22)    (dec2frac rcm2)
          (, Mcm31 Mcm32 Md) (, 1 1 1)

          vx 1.25 
          i1 (* self.i0 (/ Mcm11 Mcm12))
          i2 (* 0.5 i1 (/ Mcm21 Mcm22))

          cm1-in (np.array [[gmid-cm1 fug-cm1 (/ self.vsup 2) 0.0]])
          cm2-in (np.array [[gmid-cm2 fug-cm2 (/ self.vsup 2) 0.0]])
          cm3-in (np.array [[gmid-cm3 fug-cm3 (/ self.vsup 2) 0.0]])
          dp1-in (np.array [[gmid-dp1 fug-dp1 (/ self.vsup 2) 0.0]])

          cm1-out (first (self.nmos.predict cm1-in))
          cm2-out (first (self.pmos.predict cm2-in))
          cm3-out (first (self.nmos.predict cm3-in))
          dp1-out (first (self.nmos.predict dp1-in))

          Lcm1 (get cm1-out 1)
          Lcm2 (get cm2-out 1)
          Lcm3 (get cm3-out 1)
          Ldp1 (get dp1-out 1)

          Wcm1 (/ self.i0 (get cm1-out 0))
          Wcm2 (/ (* 0.5 i1) (get cm2-out 0))
          Wcm3 (/ i2 (get cm3-out 0))
          Wdp1 (/ (* 0.5 i1) (get dp1-out 0)) 

          sizing { "Lcm1"  Lcm1  "Lcm2"  Lcm2  "Lcm3"  Lcm3  "Ld" Ldp1
                   "Wcm1"  Wcm1  "Wcm2"  Wcm2  "Wcm3"  Wcm3  "Wd" Wdp1
                   "Mcm11" Mcm11 "Mcm21" Mcm21 "Mcm31" Mcm31
                   "Mcm12" Mcm12 "Mcm22" Mcm22 "Mcm32" Mcm32 
                   "Md"    Md }]
      (.step (super) sizing)))

  (defn render [self &optional [mode "ascii"]]
    """
    Prints an ASCII Schematic of the Symmetrical Amplifier courtesy
    https://github.com/Blokkendoos/AACircuit
    """
    (cond [(= mode "ascii")
           (print f"
o-------------o---------------o------------o--------------o----------o VDD
              |               |            |              |           
      MPCM222 +-||         ||-+ MPCM221    +-||        ||-+ MPCM212
              <-||         ||->            <-||        ||->           
              +-||----o----||-+    MPCM211 +-||----o---||-+           
              |       |       |            |       |      |           
              |       |       |            |       |      |           
              |       '-------o            o-------'      |           
              |               |            |              |           
              |               |            |              |           
              |               |            |              |           
 Iref         |            ||-+ MND11      +-||           |           
   o          |            ||<-            ->||           |           
   |          |  VI+ o-----||-+      MND12 +-||-----o VI- |           
   |          |               |     X      |              o-----o--o VO
   |          |               '-----o------'              |     |     
   |          |                     |                     |     |     
   +-|| MNCM11|           MNCM12 ||-+                     |     |     
   ->||       |                  ||<-                     |     |     
   +-||-------)------------------||-+                     |     |     
   |          |                     |                     |    --- CL
   |          |                     |                     |    ---    
   |          o-------.             |                     |     |     
   |          |       |             |                     |     |     
   |          |       |             |                     |     |     
   |   MNCM31 +-||    |             |           MNCM32 ||-+     |     
   |          ->||    |             |                  ||<-     |     
   |          +-||----o-------------)------------------||-+     |     
   |          |                     |                     |     |     
   |          |                     |                     |     |     
   '----------o---------------------o---------------------o-----'     
                                    |                                 
                                   ===                                
                                   VSS                                " )]
          [True (.render (super) mode)])))
