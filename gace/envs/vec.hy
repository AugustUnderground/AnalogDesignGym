(import os)
(import sys)
(import errno)
(import [functools [partial]])
(import [fractions [Fraction]])

(import [torch :as pt])
(import [numpy :as np])
(import [pandas :as pd])

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

(defclass VecACE []
  (defn __init__ [self ^str env-id ^int num-envs &optional 
                    ^int [n-proc (-> 0 (os.sched-getaffinity) (len) (// 2))]]
    (setv self.n-proc n-proc
          self.gace-envs (list (take num-envs (repeatedly #%(gym.make env-id))))
          self.pool (ac.to-pool (lfor e self.gace-envs e.ace)))

    (setv self.action-space (lfor env self.gace-envs env.action-space))

    (setv self.step 
          (fn [^(of list np.array) actions]
            (let [sizings (->> actions (zip self.gace-envs)
                                       (ap-map (-> it (first) (.step-fn (second it))))
                                       (enumerate) (dict))]
              (self.size-circuit-pool sizings)))))

  (defn __len__ [self] 
    (len self.gace-envs))

  (defn reset ^np.array [self]
    """
    If not running, this creates a new spectre session. The `moves` counter is
    reset, while the reset counter is increased. If `same-target` is false, a
    random target will be generated otherwise, the given one will be used.

    Finally, a simulation is run and the observed perforamnce returned.
    """

    (let [targets (lfor e self.gace-envs e.target)
          parameters (dict (enumerate (lfor e self.gace-envs
              ;; If ace does not exist, create it.
              :do (unless e.ace (setv e.ace (eval e.ace-constructor)))

              ;; Reset the step counter and increase the reset counter.
              :do (setv e.num-steps (int 0))

              ;; Clear the data log. If self.log-data == True the data will be written to
              ;; an HDF5 in the `done` function, otherwise it will be discarded.
              :do (setv e.data-log (pd.DataFrame))

              ;; Target can be random or close to a known acheivable.
              :do (setv e.target 
                          (if e.random-target
                              (target-specification e.ace-id e.ace-backend 
                                                    :random e.random-target 
                                                    :noisy e.noisy-target)
                              (dfor (, p v) (.items e.target) 
                                 [p (* v (if e.noisy-target 
                                             (np.random.normal 1.0 0.01) 
                                             1.0))])))

              ;; Starting parameters are either random or close to a known solution.
              (starting-point e.ace e.random-target e.noisy-target))))

        performances (ac.evaluate-circuit-pool self.pool 
                                               :pool-params parameters 
                                               :npar self.n-proc)]

    (list (ap-map (observation #* it) (zip (.values performances) targets)))))
      
  (defn size-circuit-pool [self sizings]
    (let [(, prev-perfs targets conds reward-fns inputs) 
          (zip #* (lfor e self.gace-envs (, (ac.current-performance e.ace) 
                                       e.target e.condition e.reward 
                                       e.input-parameters)))
             
          curr-perfs (-> self (. pool) 
                              (ac.evaluate-circuit-pool :pool-params sizings 
                                                        :npar self.n-proc) 
                              (.values))

          obs (lfor (, cp tp) (zip curr-perfs targets)
                    (observation cp tp))
          
          rew (lfor (, rf cp pp t c) 
                    (zip reward-fns curr-perfs prev-perfs targets conds)
                    (rf cp pp t c))

          td  (list (ap-map (-> (target-distance #* it) (second) (all)) 
                            (zip curr-perfs targets conds)))
          ss  (lfor e self.gace-envs (>= (inc e.num-steps) e.max-steps))
          don (list (ap-map (or #* it) (zip td ss))) 

          inf (list (ap-map (info #* it) (zip curr-perfs targets inputs)))]

      (for [(, e s p o d) (zip self.gace-envs (.values sizings) curr-perfs obs don)] 
        (setv e.num-steps (inc e.num-steps))
        (setv e.data-log (.append e.data-log (| s p) :ignore-index True))
        
        (when (and (bool e.param-log-path) 
                   (or (np.any (np.isnan o)) 
                       (np.any (np.isinf o))))
        (save-state e.ace e.ace-id e.param-log-path))
       
        (when (and (bool e.data-log-path) d)
          (save-data e.data-log e.data-log-path e.ace-id)))

      (, obs rew don inf))))
