(import os)
(import sys)
(import errno)
(import [functools [partial]])
(import [fractions [Fraction]])

(import [numpy :as np])
(import [pandas :as pd])

(import gym)
(import [gym.spaces [Dict Box Discrete MultiDiscrete Tuple]])

(import [.ace [ACE]])
(import [gace.util.func [*]])
(import [gace.util.target [*]])
(import [gace.util.render [*]])
(import [hace :as ac])

(require [hy.contrib.walk [let]]) 
(require [hy.contrib.loop [loop]])
(require [hy.extra.anaphoric [*]])
(require [hy.contrib.sequences [defseq seq]])
(import  [typing [List Set Dict Tuple Optional Union]])
(import  [hy.contrib.sequences [Sequence end-sequence]])
(import  [hy.contrib.pprint [pp pprint]])

(defclass OP9Env [ACE]
  """
  Base class for OP9
  """
  (defn __init__ [self &kwargs kwargs]
    (setv self.num-gmid 8
          self.num-fug 8
          self.num-ib 6)
    (.__init__ (super OP9Env self) #** (| kwargs {"ace_id" "op9"})))

  (defn step-v0 ^(of tuple np.array float bool dict) [self ^np.array action]
    """
    Takes an array of electric parameters for each building block and 
    converts them to sizing parameters for each parameter specified in the
    netlist. 
    """
    (let [unscaled-action (unscale-value action self.action-scale-min 
                                                self.action-scale-max)

          (, gmid-cm4 gmid-cm3 gmid-cm2 gmid-cm1 
             gmid-dp1 gmid-ls1 gmid-re1 gmid-re2) (as-> unscaled-action it
                                                      (get it (slice None 8)))
          (, fug-cm4  fug-cm3  fug-cm2  fug-cm1  
             fug-dp1  fug-ls1  fug-re1  fug-re2)  (as-> unscaled-action it
                                                      (get it (slice 8 16))
                                                      (np.power 10 it))
          (, i1 i2 i3 i4 i5 i6)                   (as-> unscaled-action it
                                                      (get it (slice -6 None))
                                                      (np.array it)
                                                      (* it 1e-6))

          i0  (get self.design-constraints "i0"   "init")
          vdd (get self.design-constraints "vsup" "init")

          M1-lim (-> self (. design-constraints) (get "Mcm43" "max") (int))
          M2-lim (-> self (. design-constraints) (get "Mcm44" "max") (int))
          M3-lim (-> self (. design-constraints) (get "Mcm42" "max") (int))
          M4-lim (-> self (. design-constraints) (get "Mcm32" "max") (int))
          M5-lim (-> self (. design-constraints) (get "Mcm33" "max") (int))
          M6-lim (-> self (. design-constraints) (get "Mcm34" "max") (int))

          M1 (-> (/ i0 i1) (Fraction) (.limit-denominator M1-lim))
          M2 (-> (/ i0 i2) (Fraction) (.limit-denominator M2-lim))
          M3 (-> (/ i0 i3) (Fraction) (.limit-denominator M3-lim))
          M4 (-> (/ i3 i4) (Fraction) (.limit-denominator M4-lim))
          M5 (-> (/ i3 i5) (Fraction) (.limit-denominator M5-lim))
          M6 (-> (/ i3 i6) (Fraction) (.limit-denominator M6-lim))

          Mcm41 M1.numerator Mcm42 M3.denominator Mcm43 M1.denominator Mcm44 M2.denominator 
          Mcm31 M4.numerator Mcm32 M4.denominator Mcm33 M5.denominator Mcm34 M6.denominator

          Mdp1 (get self.design-constraints "Md1"  "init") 
          Mcm1 (get self.design-constraints "Mcm1" "init") 
          Mcm2 (get self.design-constraints "Mcm2" "init") 
          Mls1 (get self.design-constraints "Mls1" "init") 

          dp1-in (np.array [[gmid-dp1 fug-dp1 (/ vdd 2.0)     (- (/ vdd 4.0))]])
          cm1-in (np.array [[gmid-cm1 fug-cm1 (/ vdd 4.0)               0.0  ]])
          cm2-in (np.array [[gmid-cm2 fug-cm2 (- (/ vdd 2.0))           0.0  ]])
          cm3-in (np.array [[gmid-cm3 fug-cm3 (- (/ vdd 3.0))           0.0  ]])
          cm4-in (np.array [[gmid-cm4 fug-cm4 (/ vdd 4.0)               0.0  ]])
          ls1-in (np.array [[gmid-ls1 fug-ls1 (/ vdd 6.0)               0.0  ]])
          re1-in (np.array [[gmid-re1 fug-re1 (/ vdd 3.0)               0.0  ]])
          re2-in (np.array [[gmid-re1 fug-re1 (- (/ vdd 2.0))           0.0  ]])

          dp1-out (first (self.nmos.predict dp1-in))
          cm1-out (first (self.nmos.predict cm1-in))
          cm2-out (first (self.pmos.predict cm2-in))
          cm3-out (first (self.pmos.predict cm3-in))
          cm4-out (first (self.nmos.predict cm4-in))
          ls1-out (first (self.nmos.predict ls1-in))
          re1-out (first (self.nmos.predict re1-in))
          re2-out (first (self.pmos.predict re2-in))

          Ldp1 (get dp1-out 1)
          Lcm1 (get cm1-out 1)
          Lcm2 (get cm2-out 1)
          Lcm3 (get cm3-out 1)
          Lcm4 (get cm4-out 1)
          Lls1 (get ls1-out 1)
          Lre1 (get re1-out 1)
          Lre2 (get re2-out 1)

          Wdp1 (/ i1 2.0 (get dp1-out 0)) 
          Wcm1 (/ i5     (get cm1-out 0))
          Wcm2 (/ i6     (get cm2-out 0))
          Wcm3 (/ i3     (get cm3-out 0))
          Wcm4 (/ i0     (get cm4-out 0))
          Wls1 (/ i5     (get ls1-out 0))
          Wre1 (/ i2     (get re1-out 0))
          Wre2 (/ i4     (get re2-out 0)) ]

    ;(setv self.last-action (->> unscaled-action (zip self.input-parameters) (dict)))
    (setv self.last-action (dict (zip self.input-parameters
        [ gmid-cm4 gmid-cm3 gmid-cm2 gmid-cm1 gmid-dp1 gmid-ls1 gmid-re1 gmid-re2
          fug-cm4  fug-cm3  fug-cm2  fug-cm1  fug-dp1  fug-ls1  fug-re1  fug-re2
          i1 i2 i3 i4 i5 i6 ])))

    { "Ld1" Ldp1 "Lcm1" Lcm1 "Lcm2" Lcm2 "Lcm3"  Lcm3  "Lcm4"  Lcm4  "Lls1" Lls1 "Lr1" Lre1 "Lr2" Lre2
      "Wd1" Wdp1 "Wcm1" Wcm1 "Wcm2" Wcm2 "Wcm3"  Wcm3  "Wcm4"  Wcm4  "Wls1" Wls1 "Wr2" Wre1 "Wr1" Wre2
      "Md1" Mdp1 "Mcm1" Mcm1 "Mcm2" Mcm2 "Mcm31" Mcm31 "Mcm41" Mcm41 "Mls1" Mls1  
                                         "Mcm32" Mcm32 "Mcm42" Mcm42
                                         "Mcm33" Mcm33 "Mcm43" Mcm43
                                         "Mcm34" Mcm34 "Mcm44" Mcm44
      #_/ })))

(defclass OP9XH035V0Env [OP9Env]
  """
  Implementation: xh035-3V3
  """
  (defn __init__ [self &kwargs kwargs]
    (.__init__ (super OP9XH035V0Env self) #**
               (| kwargs {"ace_backend" "xh035-3V3" "ace_variant" 0}))))
  
(defclass OP9XH035V1Env [OP9Env]
  """
  Implementation: xh035-3V3
  """
  (defn __init__ [self &kwargs kwargs]
    (.__init__ (super OP9XH035V1Env self) #**
               (| kwargs {"ace_backend" "xh035-3V3"  "ace_variant" 1}))))

(defclass OP9XH035V2Env [OP9Env]
  """
  Implementation: xh035-3V3
  """
  (defn __init__ [self &kwargs kwargs]
    (.__init__ (super OP9XH035V2Env self) #**
               (| kwargs {"ace_backend" "xh035-3V3" "ace_variant" 2}))))

(defclass OP9XH035V3Env [OP9Env]
  """
  Implementation: xh035-3V3
  """
  (defn __init__ [self &kwargs kwargs]
    (.__init__ (super OP9XH035V3Env self) #**
               (| kwargs {"ace_backend" "xh035-3V3"  "ace_variant" 3}))))

(defclass OP9XH018V0Env [OP9Env]
  """
  Implementation: xh018-1V8
  """
  (defn __init__ [self &kwargs kwargs]
    (.__init__ (super OP9XH018V0Env self) #**
               (| kwargs {"ace_backend" "xh018-1V8" "ace_variant" 0}))))
  
(defclass OP9XH018V1Env [OP9Env]
  """
  Implementation: xh018-1V8
  """
  (defn __init__ [self &kwargs kwargs]
    (.__init__ (super OP9XH018V1Env self) #**
               (| kwargs {"ace_backend" "xh018-1V8" "ace_variant" 1}))))

(defclass OP9XH018V3Env [OP9Env]
  """
  Implementation: xh018-1V8
  """
  (defn __init__ [self &kwargs kwargs]
    (.__init__ (super OP9XH018V3Env self) #**
               (| kwargs {"ace_backend" "xh018-1V8" "ace_variant" 3}))))

(defclass OP9XT018V0Env [OP9Env]
  """
  Implementation: xt018-1V8
  """
  (defn __init__ [self &kwargs kwargs]
    (.__init__ (super OP9XT018V0Env self) #**
               (| kwargs {"ace_backend" "xt018-1V8" "ace_variant" 0}))))
  
(defclass OP9XT018V1Env [OP9Env]
  """
  Implementation: xt018-1V8
  """
  (defn __init__ [self &kwargs kwargs]
    (.__init__ (super OP9XT018V1Env self) #**
               (| kwargs {"ace_backend" "xt018-1V8" "ace_variant" 1}))))

(defclass OP9XT018V3Env [OP9Env]
  """
  Implementation: xt018-1V8
  """
  (defn __init__ [self &kwargs kwargs]
    (.__init__ (super OP9XT018V3Env self) #**
               (| kwargs {"ace_backend" "xt018-1V8" "ace_variant" 3}))))

(defclass OP9GPDK180V0Env [OP9Env]
  """
  Implementation: gpdk180-1V8
  """
  (defn __init__ [self &kwargs kwargs]
    (.__init__ (super OP9GPDK180V0Env self) #**
               (| kwargs {"ace_backend" "gpdk180-1V8" "ace_variant" 0}))))
  
(defclass OP9GPDK180V1Env [OP9Env]
  """
  Implementation: gpdk180-1V8
  """
  (defn __init__ [self &kwargs kwargs]
    (.__init__ (super OP9GPDK180V1Env self) #**
               (| kwargs {"ace_backend" "gpdk180-1V8" "ace_variant" 1}))))

(defclass OP9GPDK180V3Env [OP9Env]
  """
  Implementation: gpdk180-1V8
  """
  (defn __init__ [self &kwargs kwargs]
    (.__init__ (super OP9GPDK180V3Env self) #**
               (| kwargs {"ace_backend" "gpdk180-1V8" "ace_variant" 3}))))
