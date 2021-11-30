(import os)
(import yaml)
(import logging)
(import [functools [partial]])
(import [fractions [Fraction]])
(import [datetime [datetime :as dt]])
(import [numpy :as np])
(import [h5py :as h5])
(import [hace :as ac])
(import gym)
(import gace)
(import [operator [itemgetter]])
(require [hy.contrib.walk [let]]) 
(require [hy.contrib.loop [loop]])
(require [hy.extra.anaphoric [*]])
(import [hy.contrib.pprint [pp pprint]])

(setv env (gym.make "gace:nand4-xh035-v1"))
(setv obs (.reset env))
(gace.check-env env)

(setx act (.sample env.action-space))
(pp (setx ob (.step env act)))

(for [i [1 2 3 4 5 6 8 9]]
  (setv env (gym.make f"gace:op{i}-xh035-v1"))
  (print f"TESTING op{i} v1")
  (gace.check-env env)
  (.close env) (del env) )





(for [o [1 2 3 4 5 6 8 9]]
  (setv op f"op{o}")
  (setv env0 (gym.make f"gace:{op}-gpdk180-v0"))
  ;(setv env1 (gym.make f"gace:{op}-gpdk180-v1"))
  (print f"TESTING {op} v0")
  (gace.check-env env0)
  ;(print f"TESTING {op} v1")
  ;(gace.check-env env1)
  (.close env0) 
  ;(.close env1)
  (del env0) 
  ;(del env1)
  #_/ )

(check-env env :warn True)

(env.reset)

(list (map #%(unscale-value #* %1) (zip foo env.action-scale-min env.action-scale-max)))

(setv (, o r d i) (env.step (np.array bar)))



(setx obs (.reset env))
(setx act (.sample env.action-space))
(setx ob (.step env act))

(for [i (range 10)]
  (setv act (.sample env.action-space))
  (setv ob (.step env act))
  (pp (get ob 1)))

