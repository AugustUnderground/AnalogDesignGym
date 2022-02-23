(import os)
(import sys)
(import errno)
(import datetime)
(import [functools [partial]])
(import [fractions [Fraction]])

(import [numpy :as np])

(import [pyarrow :as pa])
(import [pyarrow [feather :as ft]])

(import gym)

(import [gace.util.func [*]])
(import [gace.util.prim [*]])
(import [gace.util.target [*]])
(import [gace.util.render [*]])

(require [hy.contrib.walk [let]]) 
(require [hy.contrib.loop [loop]])
(require [hy.extra.anaphoric [*]])
(require [hy.contrib.sequences [defseq seq]])
(import  [typing [List Set Dict Tuple Optional Union Callable]])
(import  [hy.contrib.sequences [Sequence end-sequence]])
(import  [hy.contrib.pprint [pp pprint]])

(defclass ACE [gym.Env]
  """
  Base class interfacing both ACE and gym.
  Arguments:
    ace-id: str                         -> ACE Identifier ∈ [op#, st1, nand4]
    ace-backend: str                    -> ACE Backend ∈ [xh035, sky130, gpdk180]
  Optional:
    ckt-path: str (None)                -> Path to ACE Testbench
    pdk-path: str (None)                -> Path to PDK
    obs-lo: Union[float, np.array] -Inf -> Lower bound of obs
    obs-hi: Union[float, np.array] +Inf -> Upper bound of obs
    max-steps: int (666)                -> Maximum number of steps before reset
    target: Dict[str, float] ({})       -> Specific Target to reach
    random-target: bool (False)         -> Randomize Target each episode
    noisy-target: bool  (True)          -> Add some noise after each reset
    train-mode: bool (True)             -> Whether this is training or eval
    custom-reward: function (None)      -> A custom reward function
    reltol: float (1e-3)                -> Relative tolarnce for equaltiy
    data-log-path: str ("")             -> Write a dataframe to HDF5 at this location
  """
  (setv metadata {"render.modes" ["human" "ascii"]})

  (defn __init__ [self ^str ace-id ^str ace-backend ^int ace-variant &optional 
                       ^str [ckt-path None] ^str [pdk-path None]
                       ^(of Union float np.array) [obs-lo (- Inf)]
                       ^(of Union float np.array) [obs-hi Inf]
                       ^int [max-steps 100] ^(of dict str float) [design-constr {}]
                       ^(of dict str float) [target {}] ^float [reltol 1e-3]
                       ^bool [random-target False] ^bool [noisy-target True]
                       ^bool [train-mode True] 
                       ^(of Callable)   [custom-reward None]
                       ^(of gym.spaces) [custom-action None]
                       ^(of np.array)   [custom-action-lo None]
                       ^(of np.array)   [custom-action-hi None]
                       ^str [nmos-path None] ^str [pmos-path None]
                       ^str [data-log-path None] ^bool [logging-enabled True]]

    ;; ACE Configuration
    (setv self.ace-id          ace-id
          self.ace-backend     ace-backend
          self.ace-variant     ace-variant
          self.ace-constructor (ace-constructor self.ace-id self.ace-backend 
                                                :ckt ckt-path :pdk [pdk-path])
          self.ace             (eval self.ace-constructor))

    ;; Obtain design constraints from ACE backend and override if given
    (setv dc (design-constraints self.ace)
          self.design-constraints (dfor k (.keys dc) 
                                          [k (.get design-constr k 
                                                   (get dc k))]))

    ;; Generate action space for the given ACE Environment
    (setv (, self.action-space  
          self.action-scale-min
          self.action-scale-max) (if custom-action 
                                    (, custom-action 
                                       custom-action-lo 
                                       custom-action-hi) 
                                    (action-space self.ace
                                                  self.design-constraints 
                                                  self.ace-id 
                                                  self.ace-variant)))

    ;; Input Scaling Functions
    (setv self.scale-action #%(scale-value %1 self.action-scale-min self.action-scale-max))
    (setv self.unscale-action #%(unscale-value %1 self.action-scale-min self.action-scale-max))

    ;; Set training mode by default
    (setv self.train-mode train-mode)

    ;; Environment Configurations
    (setv self.max-steps max-steps
          self.num-steps (int 0))

    ;; If a target was provided, use it during but add some noise during each iteration.
    (setv self.random-target random-target
          self.noisy-target  noisy-target
          self.target        (or target 
                                 (target-specification self.ace-id 
                                                       self.design-constraints
                                                       :random self.random-target
                                                       :noisy self.noisy-target))
          self.reltol        reltol
          self.reward        (or custom-reward absolute-reward)
          ;self.reward        (or custom-reward simple-reward)
          ;self.reward        (or custom-reward relative-reward)
          self.condition     (reward-condition self.ace-id :tolerance self.reltol))

    ;; The `Box` type observation space consists of perforamnces, the distance
    ;; to the target, as well as general information about the current
    ;; operating point.
    (setv obs-shape (observation-shape self.ace self.ace-id 
                                       (-> self.target (.keys) (list)))
          self.observation-space (Box :low obs-lo :high obs-hi 
                                      :shape obs-shape
                                      :dtype np.float32))

    ;; Primitive Device setup
    (when (in self.ace-variant [0 2])
      (setv self.nmos (load-primitive "nmos" self.ace-backend :dev-path nmos-path)
            self.pmos (load-primitive "pmos" self.ace-backend :dev-path pmos-path)))

    ;; Specify Input Parameter Names
    (setv self.input-parameters (input-parameters self.ace self.ace-id 
                                                  self.ace-variant))

    ;; Initialize the Reset counter
    (setv self.reset-count -1)

    ;; Data Logging
    (setv self.logging-enabled logging-enabled)
    (when self.logging-enabled
      (setv time-stamp (-> datetime (. datetime) (.now) (.strftime "%Y%m%d-%H%M%S"))
            self.data-log-path (or data-log-path f"/tmp/gace/{time-stamp}-{ace-id}")
            self.data-log (initialize-data-log self.ace self.target self.reset-count))
      (os.makedirs self.data-log-path :exist-ok True))

    ;; Override step function
    (setv self.step-fn (cond [(= self.ace-variant 0) self.step-v0] 
                             [(= self.ace-variant 1)
                              (partial sizing-step self.input-parameters 
                                                   self.action-scale-min 
                                                   self.action-scale-max)]
                             [(= self.ace-variant 2) self.step-v2]
                             [(= self.ace-variant 3)
                              (partial sizing-step-relative self.input-parameters
                                                            self.design-constraints  
                                                            self.ace)])
          self.step 
            (fn [^np.array action &optional [blocklist []]]
              (-> action (self.step-fn) (self.size-circuit :blocklist blocklist))))

    ;; Get an unscaled sample of the action space. This gives actual values,
    ;; i.e. not ∈ [-1;1]
    ;; Just convenience for sampling and unscaling manually.
    (setv self.unscaled-sample #%(->> self
                                      (. action-space)
                                      (.sample) 
                                      (self.unscale-action)
                                      (zip self.input-parameters)
                                      (dict )))

    ;; Convenience function for taking a step with real (unscaled) action.
    (setv self.unscaled-step #%(-> %1 (self.scale-action) (self.step)))

    ;; Call gym.Env constructor
    (.__init__ (super ACE self)))

  (defn random-step [self]
  """
  Convenience function in case you say to yourself:
  'But I just wanna take a random step.'
  Mostly for testing the environment etc.
  """
    (-> self (. action-space) (.sample) (self.step)))


  (defn reset ^np.array [self]
    """
    If not running, this creates a new spectre session. The `moves` counter is
    reset, while the reset counter is increased. If `same-target` is false, a
    random target will be generated otherwise, the given one will be used.

    Finally, a simulation is run and the observed perforamnce returned.
    """

    ;; If ace does not exist, create it.
    (unless self.ace
      (setv self.ace (eval self.ace-constructor)))

    ;; Reset the step counter and increase the reset counter.
    (setv self.num-steps   (int 0)
          self.reset-count (inc self.reset-count))

    ;; Target can be random or close to a known acheivable.
    (setv self.target (if self.random-target
      (target-specification self.ace-id self.design-constraints ; self.ace-backend 
                            :random self.random-target 
                            :noisy self.noisy-target)
      (dfor (, p v) (.items self.target) 
            [p (* v (if self.noisy-target (np.random.normal 1.0 0.01) 1.0))])))

    ;; Starting parameters are either random or close to a known solution.
    (setv parameters (starting-point self.ace self.random-target self.noisy-target))

    ;; Get the current performance for the initial parameters
    (setv performance (ac.evaluate-circuit self.ace :params parameters))

    ;; Identifiers for elements in observation
    (setv self.info (info performance self.target self.input-parameters))

    (observation performance self.target 0 self.max-steps))

  (defn size-circuit [self sizing &optional [blocklist []]]
    (let [prev-perf (ac.current-performance self.ace)
          curr-perf (ac.evaluate-circuit self.ace :params sizing
                                                  :blocklist blocklist) 

          steps (inc self.num-steps)
          obs (observation curr-perf self.target steps self.max-steps)
          rew (self.reward curr-perf prev-perf self.target self.condition 
                           steps self.max-steps)
          don (or (>= steps self.max-steps) 
                  (all (second (target-distance curr-perf 
                                                self.target 
                                                self.condition))))
          inf (info curr-perf self.target self.input-parameters) ]

      ;; Data Logging
      (when self.logging-enabled
        (self.log-data))

      (setv self.num-steps steps)
      (, obs rew don inf)))

  (defn log-data [self]
    (let [sizing (ac.current-sizing self.ace)
          performance (ac.current-performance self.ace)

          (, sn_ sd_) (list (map list (zip #* (lfor (, p s) (.items sizing) 
                                                (, p (pa.array [s] :type (.float32 pa)))))))
          sn (+ ["episode" "step"] (sorted sn_))
          sd (+ [(pa.array [self.reset-count] :type (.float32 pa)) 
                 (pa.array [self.num-steps]   :type (.float32 pa))] sd_)
          sizing-table (pa.table sd :names sn)

          pn_ (list (reduce + (.values (sorted-parameters performance))))
          pd_ (lfor p pn_ (pa.array [(get performance p)] :type (.float32 pa)))
          pn (+ ["episode" "step"] pn_)
          pd (+ [(pa.array [self.reset-count] :type (.float32 pa))
                 (pa.array [self.num-steps]   :type (.float32 pa))] pd_)
          performance-table (pa.table pd :names pn) ]

      (setv (get self.data-log "sizing") (-> [sizing-table (get self.data-log "sizing")] 
                                             (pa.concat-tables) (.combine-chunks))
            (get self.data-log "performance") (-> [performance-table (get self.data-log "performance")] 
                                             (pa.concat-tables) (.combine-chunks)))
      (ft.write-feather (get self.data-log "performance") 
                        (+ self.data-log-path "/performance.ft"))
      (ft.write-feather (get self.data-log "sizing") 
                        (+ self.data-log-path "/sizing.ft"))))

  (defn render [self &optional ^str [mode "human"]]
    (print (ascii-schematic self.ace-id)))

  (defn seed [self rng-seed]
    """
    Sets The RNG Seed for this environment.
    """
    (.seed np.random rng-seed)
    (.manual-seed pt rng-seed)
    rng-seed)

  (defn close [self]
    """
    Closes the spectre session.
    """
    (.stop self.ace)
    (del self.ace)
    (setv self.ace None)))
