(import os)
(import yaml)
(import logging)
(import [functools [partial]])
(import [datetime [datetime :as dt]])
(import [icecream [ic]])
(import [numpy :as np])
(import [h5py :as h5])
(import [hace :as ac])
(import gym)
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

(setv nmos-path f"../models/xh035-nmos"
      pmos-path f"../models/xh035-pmos"
      pdk-path  f"/mnt/data/pdk/XKIT/xh035/cadence/v6_6/spectre/v6_6_2/mos"
      moa-path  f"{HOME}/Workspace/ACE/ace/resource/xh035-3V3/op6"
      sym-path  f"{HOME}/Workspace/ACE/ace/resource/xh035-3V3/op2"
      sym-env-name "gym_ad:sym-amp-xh035-v0"
      moa-env-name "gym_ad:miller-amp-xh035-v0"
      mod-env-name "gym_ad:miller-amp-xh035-v1"
      )

;; Create Environment
(setv env (gym.make mod-env-name
                    :pdk-path        pdk-path
                    :ckt-path        moa-path
                    :nmos-path       nmos-path
                    :pmos-path       pmos-path
                    :data-log-prefix data-path
                    :random-target   False))

;; Check if no Warnings
(check-env env :warn True)

(setv foo [-1.0 -0.36093295 1.0 0.43878222 0.00887966 0.98940694
           -0.6869546 -1.0 -0.02716774 -0.43879426])

(setv bar [-0.08755815 0.69160175 0.3732996 1.0 -0.166852 
           0.8064401 0.13569689 -1.0 -1.0 0.8056166])

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

