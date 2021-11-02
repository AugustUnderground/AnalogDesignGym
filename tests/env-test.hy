(import os)
(import yaml)
(import logging)
(import [functools [partial]])
(import [datetime [datetime :as dt]])
(import [numpy :as np])
(import [h5py :as h5])
(import [hace :as ac])
(import gym)
(import gace)
(import [operator [itemgetter]])
(import [stable-baselines3.common.env-checker [check-env]])
(require [hy.contrib.walk [let]]) 
(require [hy.contrib.loop [loop]])
(require [hy.extra.anaphoric [*]])
(import [hy.contrib.pprint [pp pprint]])

(setv HOME       (os.path.expanduser "~")
      time-stamp (-> dt (.now) (.strftime "%H%M%S-%y%m%d"))
      model-path f"./models/baselines/a2c-miller-amp-xh035-{time-stamp}.mod"
      ;model-path f"./models/baselines/a2c-sym-amp-xh035-{time-stamp}.mod"
      ;model-path f"./models/baselines/a2c-sym-amp-xh035-100456-210903.mod"
      data-path  f"../data/symamp/xh035")

(setv ;nmos-path f"../models/xh035-nmos"
     nmos-path f"/mnt/data/share/xh035-nmos-20211022-091316"
      ;pmos-path f"../models/xh035-pmos"
      pmos-path f"/mnt/data/share/xh035-pmos-20211022-084243"
      pdk-path  f"/mnt/data/pdk/XKIT/xh035/cadence/v6_6/spectre/v6_6_2/mos"
      op1-path  f"{HOME}/Workspace/ACE/ace/resource/xh035-3V3/op1"
      op2-path  f"{HOME}/Workspace/ACE/ace/resource/xh035-3V3/op2"
      op3-path  f"{HOME}/Workspace/ACE/ace/resource/xh035-3V3/op3"
      op4-path  f"{HOME}/Workspace/ACE/ace/resource/xh035-3V3/op4"
      op6-path  f"{HOME}/Workspace/ACE/ace/resource/xh035-3V3/op6"
      nd4-path   f"{HOME}/Workspace/ACE/ace/resource/xh035-3V3/nand4"
      #_/ )

;; Create Environment
(setv env (gym.make "gace:op2-xh035-v0"
                    :pdk-path        pdk-path
                    :ckt-path        op2-path
                    :nmos-path       nmos-path
                    :pmos-path       pmos-path
                    :data-log-prefix data-path
                    :random-target   False))


(lfor _ (range 10) (env.observation-space.contains (.reset env)))


(gace.check-env env)

;; GEOM
(setv env (gym.make "gace:nand4-xh035-v1"
                    :pdk-path        pdk-path
                    :ckt-path        nd4-path
                    :data-log-prefix data-path
                    :random-start   False))

;; Check if no Warnings
(check-env env :warn True)

(env.reset)

(list (map #%(unscale-value #* %1) (zip foo env.action-scale-min env.action-scale-max)))

(setv (, o r d i) (env.step (np.array bar)))



;; One step test
(setx obs (.reset env))
(setx act (.sample env.action-space))
(setx ob (.step env act))

;; Ten step test
(for [i (range 10)]
  (setv act (.sample env.action-space))
  (setv ob (.step env act))
  (pp (get ob 1)))

