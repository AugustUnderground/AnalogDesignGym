(import os)
(import sys)
(import errno)
(import [functools [partial]])

(import [torch :as pt])
(import [numpy :as np])
(import [pandas :as pd])

(import [skopt [gp-minimize]])

(import gym)
(import [gym.spaces [Dict Box Discrete MultiDiscrete Tuple]])

(import [pettingzoo [AECEnv ParallelEnv]])
(import [pettingzoo.utils [agent-selector wrappers from-parallel]])

(import ray)
(import [ray.rllib.env.multi-agent-env [MultiAgentEnv]])

(import [.amp_env [AmplifierXH035Env]])
(import [.util [*]])

(require [hy.contrib.walk [let]]) 
(require [hy.contrib.loop [loop]])
(require [hy.extra.anaphoric [*]])
(require [hy.contrib.sequences [defseq seq]])
(import [hy.contrib.sequences [Sequence end-sequence]])
(import [hy.contrib.pprint [pp pprint]])

;; THIS WILL BE FIXED IN HY 1.0!
;(import multiprocess)
;(multiprocess.set-executable (.replace sys.executable "hy" "python"))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; Single Agent
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

(defclass SymAmpXH035Env [AmplifierXH035Env]
  """
  Derived amplifier class, implementing the Symmetrical Amplifier in the XFAB
  XH035 Technology. Only works in combinatoin with the right netlists.
  Observation Space:
    - See AmplifierXH035Env

  Action Space:
    Continuous Box a: (10,) ∈ [1.0;1.0]

    Where
    a = [ gmid-cm1 gmid-cm2 gmid-cm3 gmid-dp1 
          fug-cm1  fug-cm2  fug-cm3  fug-dp1 
          mcm1 mcm2 ] 

      mcm1 and mcm2 are the mirror ratios of the corresponding current mirrors.
  """

  (setv metadata {"render.modes" ["human" "ascii"]})

  (defn __init__ [self &optional ^str [pdk-path None] ^str [ckt-path None] 
                                 ^str [nmos-path None] ^str [pmos-path None] 
                                 ^int [max-moves 200] ^float [target-tolerance 1e-3] 
                                 ^bool [random-target False]
                                 ^dict [target None] ^str [data-log-prefix ""]]
    """
    Constructs a Symmetrical Amplifier Environment with XH035 device models and
    the corresponding netlist.
    Arguments:
      pdk-path:   This will be passed to the ACE backend.
      ckt-path:   This will be passed to the ACE backend.
      nmos-path:  Prefix path, expects to find `nmos-path/model.pt`, 
                  `nmos-path/scale.X` and `nmos-path/scale.Y` at this location.
      pmos-path:  Same as 'nmos-path', but for PMOS model.
      max-moves:  Maximum amount of steps the agent is allowed to take per
                  episode, before it counts as failed. Default = 200.
      target-tolerance: (| target - performance | <= tolerance) ? Success.
      random-target: Generate new random target for each episode.
      target: Specific target, if given, no random targets will be generated,
              and the agent tries to find the same one over and over again.

    """

    ;; Specify constants as they are defined in the netlist and by the PDK.
    (setv self.vs   0.5       ; Some voltage 
          self.cl   5e-12     ; Load Capacitance
          self.rl   100e6     ; Load Resistance
          self.i0   3e-6      ; Bias Current
          self.vsup 3.3       ; Supply Voltage
          self.fin  1e3       ; Input Frequency
          self.rs   100       ; Sheet Resistance
          self.cx   0.85e-15)

    ;; Check given paths
    (unless (or pdk-path (not (os.path.exists pdk-path)))
      (raise (FileNotFoundError errno.ENOENT 
                                (os.strerror errno.ENOENT) 
                                pdk-path)))
    (unless (or ckt-path (not (os.path.exists ckt-path)))
      (raise (FileNotFoundError errno.ENOENT 
                                (os.strerror errno.ENOENT) 
                                ckt-path)))

    ;; Initialize parent Environment.
    (.__init__ (super SymAmpXH035Env self) AmplifierID.SYMMETRICAL 
                                           [pdk-path] ckt-path
                                           nmos-path pmos-path
                                           max-moves target-tolerance
                                           :data-log-prefix data-log-prefix
                                           #_/ )

    ;; Generate random target of None was provided.
    (setv self.random-target random-target
          self.target        (or target 
                                 (self.target-specification :random random-target
                                                            :noisy True)))

    ;; Specify geometric and electric parameters, these have to align with the
    ;; parameters defined in the netlist.
    (setv self.geometric-parameters [ "Lcm1" "Lcm2" "Lcm3" "Ld" 
                                      "Mcm11" "Mcm12" "Mcm21" "Mcm22" 
                                      "Mcm31" "Mcm32" "Md"
                                      "Wcm1" "Wcm2" "Wcm3" "Wd" ]
          self.electric-parameters [ "gmid_cm1" "gmid_cm2" "gmid_cm3" "gmid_dp1" 
                                     "fug_cm1" "fug_cm2" "fug_cm3" "fug_dp1" 
                                     "mcm1" "rmc2" ])

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

    ;; The `Box` type observation space consists of perforamnces, the distance
    ;; to the target, as well as general information about the current
    ;; operating point.
    (setv self.observation-space (Box :low (- np.inf) :high np.inf 
                                      :shape (, 245)  :dtype np.float32)))

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
             mcm1 mcm2 ) (unscale-value action self.action-scale-min 
                                               self.action-scale-max)
          
          (, Mcm11 Mcm12)      (dec-to-frac mcm1)
          (, Mcm21 Mcm22)      (dec-to-frac mcm2)
          (, Mcm31 Mcm32 Mdp1) (, 2 2 2)

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
                   "Md"    Mdp1 }]

      (.size-step (super) (self.clip-sizing sizing))))
  
  (defn clip-sizing ^dict [self ^dict sizing]
    """
    Clip the chosen values according to PDK Specifiactions.
    """
    (dfor (, p v) (.items sizing)
      [p (cond [(.startswith p "M") (max v 1.0)]
               [(.startswith p "L") (max v 0.35e-6)]
               [(.startswith p "W") (-> v (max 0.4e-6) (min 150e-6))]
               [True v])]))

  (defn target-specification ^dict [self &optional ^bool [random False] 
                                                   ^bool [noisy True]]
    """
    Generate a noisy target specification.
    """
    (let [ts {"a_0"         55.0                                      
              "ugbw"        (np.array [3500000.0 4000000.0])
              "pm"          65.0
              "gm"          -30.0
              "sr_r"        (np.array [3500000.0 4000000.0])
              "sr_f"        (np.array [-3500000.0 -4000000.0])
              "vn_1Hz"      5e-06
              "vn_10Hz"     2e-06
              "vn_100Hz"    5e-07
              "vn_1kHz"     1.5e-07
              "vn_10kHz"    5e-08
              "vn_100kHz"   2.5e-08
              "psrr_n"      80.0
              "psrr_p"      80.0
              "cmrr"        80.0
              "v_il"        0.9
              "v_ih"        3.2
              "v_ol"        0.1
              "v_oh"        3.2
              "i_out_min"   -7e-5
              "i_out_max"   7e-5
              "overshoot_r" 2.0
              "overshoot_f" 2.0
              "voff_stat"   3e-3
              "voff_sys"    1.5e-3
              "A"           5.5e-10
              #_/ }
          factor (cond [random (np.abs (np.random.normal 1 0.5))]
                       [noisy  (np.random.normal 1 0.01)]
                       [True   1.0])]
      (dfor (, p v) (.items ts)
        [ p (if noisy (* v factor) v) ])))

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

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; Multi Agent
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

(defn sym-env [&kwargs kwargs]
  (-> (sym-raw #** kwargs)
      (wrappers.CaptureStdoutWrapper)
      ;(wrappers.AssertOutOfBoundsWrapper)
      (wrappers.OrderEnforcingWrapper)))

(defn sym-raw [&kwargs kwargs]
  (-> (SymAmpXH035ZooMA #** kwargs)
      (from-parallel)))

(defclass SymAmpXH035ZooMA [ParallelEnv SymAmpXH035Env]
  (setv metadata {"render.modes" ["human"] "name" "sym-amp-xh035-v1"})

  (defn __init__ [self &kwargs kwargs]
    (SymAmpXH035Env.__init__ self #** kwargs)

    (setv self.possible-agents ["pcm_2" "ndp_1" "ncm_1" "ncm_3"]
          self.agent-name-mapping (dict (zip self.possible-agents
                                             (-> self.possible-agents 
                                                 (len) (range) (list)))))
    
    (setv self.action-spaces 
            { "pcm_2" (Box :low -1.0 :high 1.0 :shape (, 3)
                           :dtype np.float32)
              "ndp_1" (Box :low -1.0 :high 1.0 :shape (, 3)
                           :dtype np.float32)
              "ncm_1" (Box :low -1.0 :high 1.0 :shape (, 3)
                           :dtype np.float32)
              "ncm_3" (Box :low -1.0 :high 1.0 :shape (, 3)
                           :dtype np.float32) })

    (setv self.observation-spaces 
            (dfor agent self.possible-agents
              [agent (Box :low (np.nan-to-num (- np.inf)) 
                          :high (np.nan-to-num np.inf)
                          :shape (, 201) :dtype np.float32)])))

  (defn observe [self agent]
    (get self.observations agent))

  (defn reset [self]
    ;; Reset Agent cycle
    (setv self.agents (get self.possible-agents (slice None None)))

    ;; Get observation from parent class
    (setv obs (SymAmpXH035Env.reset self))
    (dfor agent self.agents [agent obs]))

  (defn observation-space [self agent]
    (get self.observation-spaces agent))
  
  (defn action-space [self agent]
    (get self.action-spaces agent))

  (defn _forall-agents [self same-value]
    (dfor agent self.agents
          [agent same-value]))

  (defn step [self actions]
    (let [(, gmid-cm1 fug-cm1 mcm1) (get actions "ncm_1")
          (, gmid-cm2 fug-cm2 mcm2) (get actions "pcm_2")
          (, gmid-dp1 fug-dp1 _)    (get actions "ndp_1")
          (, gmid-cm3 fug-cm3 _)    (get actions "ncm_3")
          action (np.array [gmid-cm1 gmid-cm2 gmid-cm3 gmid-dp1
                            fug-cm1  fug-cm2  fug-cm3  fug-dp1 
                            mcm1 mcm2])
          (, o r d i) (SymAmpXH035Env.step self action) 
          observations (self._forall-agents o)
          rewards (self._forall-agents r)
          dones (self._forall-agents d)
          infos (self._forall-agents i) ]
      (, observations rewards dones infos))))

(defclass SymAmpXH035RayMA [MultiAgentEnv SymAmpXH035Env]
  (defn __init__ [self config]
    (SymAmpXH035Env.__init__ self #** config)
    (setv self.building-blocks ["pcm_2" "ndp_1" "ncm_1" "ncm_3"]))

  (defn _forall-bb [self same-value]
    (dfor bb self.building-blocks
          [bb same-value]))

  #@(staticmethod
  (defn policy-config ^tuple []
    (let [obs-space (Box :low (np.nan-to-num (- np.inf)) 
                         :high (np.nan-to-num np.inf)
                         :shape (, 203) :dtype np.float32)
        act-space-dp (Box :low -1.0 :high 1.0 :shape (, 2) :dtype np.float32)
        act-space-cm (Box :low -1.0 :high 1.0 :shape (, 3) :dtype np.float32)

        policies { "ncm" (, None obs-space act-space-cm {})
                   "pcm" (, None obs-space act-space-cm {})
                   "ndp" (, None obs-space act-space-cm {})
                   "pdp" (, None obs-space act-space-cm {}) }
        policy-mapping (fn [a e w &kwargs kw] (get a (slice 0 3))) ]
      (, policies policy-mapping))))

  (defn reset [self]
    (let [obs (SymAmpXH035Env.reset self)]
      (self._forall-bb obs)))

  (defn step ^dict [self ^dict actions]
    (let [(, gmid-cm1 fug-cm1 mcm1) (get actions "ncm_1")
          (, gmid-cm2 fug-cm2 mcm2) (get actions "pcm_2")
          (, gmid-dp1 fug-dp1)      (get actions "ndp_1")
          (, gmid-cm3 fug-cm3 _)    (get actions "ncm_3")
          action                    (np.array [gmid-cm1 gmid-cm2 gmid-cm3 gmid-dp1
                                               fug-cm1  fug-cm2  fug-cm3  fug-dp1 
                                               mcm1 mcm2])
          (, o r d i)               (SymAmpXH035Env.step self action) 
          observations              (self._forall-bb o)
          rewards                   (self._forall-bb r)
          dones                     (self._forall-bb d)
          _                         (setv (get dones "__all__") 
                                          (-> dones (.values) (all)))
          infos                     (self._forall-bb i)]
      (, observations rewards dones infos))))
