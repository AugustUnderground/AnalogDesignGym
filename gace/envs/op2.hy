(import os)
(import sys)
(import errno)
(import [functools [partial]])
(import [fractions [Fraction]])

(import [numpy :as np])
(import [pandas :as pd])

(import [.ace [ACE]])
(import [gace.util.func [*]])
(import [gace.util.target [*]])
(import [gace.util.render [*]])
(import [hace :as ac])

(require [hy.contrib.walk [let]]) 
(require [hy.contrib.loop [loop]])
(require [hy.extra.anaphoric [*]])
(require [hy.contrib.sequences [defseq seq]])
(import  [typing [List Set Optional Union]])
(import  [hy.contrib.sequences [Sequence end-sequence]])
(import  [hy.contrib.pprint [pp pprint]])

(defclass OP2Env [ACE]
  """
  Base class for OP2
  """
  (defn __init__ [self &kwargs kwargs]
    (.__init__ (super OP2Env self) #** (| kwargs {"ace_id" "op2"})))

  (defn step-v0 ^(of tuple np.array float bool dict) [self ^np.array action 
             &optional ^(of list str) [blocklist []]]
    """
    Takes an array of electric parameters for each building block and 
    converts them to sizing parameters for each parameter specified in the
    netlist. 
    """
    (let [unscaled-action (unscale-value action self.action-scale-min 
                                                self.action-scale-max)

          (, gmid-cm1 gmid-cm2 gmid-cm3 gmid-dp1) (as-> unscaled-action it
                                                      (get it (slice None 4)))
          (, fug-cm1  fug-cm2  fug-cm3  fug-dp1 ) (as-> unscaled-action it
                                                      (get it (slice 4 8))
                                                      (np.power 10 it))
          (, i1 i2 )                              (as-> unscaled-action it
                                                      (get it (slice -2 None))
                                                      (np.array it)
                                                      (* it 1e-6))

          i0  (get self.design-constraints "i0"   "init")
          vdd (get self.design-constraints "vsup" "init")
          
          M1-lim (-> self (. design-constraints) (get "Mcm12" "max") (int))
          M2-lim (-> self (. design-constraints) (get "Mcm22" "max") (int))

          M1 (-> (/ i0     i1) (Fraction) (.limit-denominator M1-lim))
          M2 (-> (/ i1 2.0 i2) (Fraction) (.limit-denominator M2-lim))

          Mcm11 M1.numerator Mcm12 M1.denominator
          Mcm21 M2.numerator Mcm22 M2.denominator
          
          Mdp1  (get self.design-constraints "Md"    "init")
          Mcm31 (get self.design-constraints "Mcm31" "init") 
          Mcm32 (get self.design-constraints "Mcm32" "init")

          dp1-in (np.array [[gmid-dp1 fug-dp1 (/ vdd 2.0) (- (/ vdd 4.0))]])
          cm1-in (np.array [[gmid-cm1 fug-cm1 (/ vdd 4.0)           0.0  ]])
          cm2-in (np.array [[gmid-cm2 fug-cm2 (/ vdd 3.0)           0.0  ]])
          cm3-in (np.array [[gmid-cm3 fug-cm3 (/ vdd 4.0)           0.0  ]])

          dp1-out (first (self.nmos.predict dp1-in))
          cm1-out (first (self.nmos.predict cm1-in))
          cm2-out (first (self.pmos.predict cm2-in))
          cm3-out (first (self.nmos.predict cm3-in))

          Ldp1 (get dp1-out 1)
          Lcm1 (get cm1-out 1)
          Lcm2 (get cm2-out 1)
          Lcm3 (get cm3-out 1)

          Wdp1 (/ i1 2.0 (get dp1-out 0) Mdp1) 
          Wcm1 (/ i0     (get cm1-out 0) Mcm11)
          Wcm2 (/ i1 2.0 (get cm2-out 0) Mcm21)
          Wcm3 (/ i2     (get cm3-out 0) Mcm31) ]

    (setv self.last-action (->> unscaled-action (zip self.input-parameters) (dict)))

    { "Ld" Ldp1 "Lcm1"  Lcm1  "Lcm2"  Lcm2  "Lcm3"  Lcm3 
      "Wd" Wdp1 "Wcm1"  Wcm1  "Wcm2"  Wcm2  "Wcm3"  Wcm3 
      "Md" Mdp1 "Mcm11" Mcm11 "Mcm21" Mcm21 "Mcm31" Mcm31 
                "Mcm12" Mcm12 "Mcm22" Mcm22 "Mcm32" Mcm32 }))

  (defn step-v2 ^(of tuple np.array float bool dict) [self ^int action-idx
          &optional ^(of list str) [blocklist []]]
    """
    Takes an array of descrete electric parameters for each building block and 
    converts them to sizing parameters for each parameter specified in the
    netlist. 
    """
    (if (= 0 action-idx)
        (ac.current-sizing self.ace)
        (let [current-performance (ac.current-performance self.ace)

              current-params (np.array (lfor p self.input-parameters
                                             (cond [(.endswith p ":fug") 
                                                    (np.log10 (get current-performance p))]
                                                   [(.endswith p ":id") 
                                                    (* (get current-performance p) 1.0e6)]
                                                   [True (get current-performance p)])))

              grid-action (np.array 
                            (+ (-> self.design-constraints (get "gmoverid" "grid") (repeat 4) (list))
                               (-> self.design-constraints (get "fug" "grid") (repeat 4) (list))
                               (-> 0.1 (repeat 2) (list))))


              (, up dn) (np.array-split (get (np.eye (* 2 (len self.input-parameters))) 
                                             (- action-idx 1)) 2)
              
              absolute-action (+ current-params (* grid-action (- up dn))) 

              scaled-action (scale-value absolute-action self.action-scale-min 
                                                         self.action-scale-max) ]

          (self.step-v0 scaled-action :blocklist blocklist))))

  (defn step-v5 ^(of tuple np.array float bool dict) [self ^tuple action]
    """
    Same step as v0, but with the option to block certain simulation analyses.
    """
    (let [design-action     (first action)
          simulation-action (simulation-mask self.ace (second action))
          pi                (ac.performance-identifiers 
                                self.ace :blocklist simulation-action)
          performances      (flatten (lfor p pi [(.format "performance_{}" p)
                                                 (.format "target_{}" p)
                                                 (.format "distance_{}" p)]))
          (, obs  reward 
             done info)     (self.step-v0 design-action 
                                     :blocklist (if self.train [] 
                                                    simulation-action))

          obs-mask          (np.array (lfor op (get info "output-parameters") 
                                               (int (in op performances))))

          observations      (* obs obs-mask) ]

      (, observations reward done info))))

(defclass OP2XH035V0Env [OP2Env]
  """
  Implementation: xh035-3V3
  """
  (defn __init__ [self &kwargs kwargs]
    (.__init__ (super OP2XH035V0Env self) #**
               (| kwargs {"ace_backend" "xh035-3V3" "ace_variant" 0}))))

(defclass OP2XH035V1Env [OP2Env]
  """
  Implementation: xh035-3V3
  """
  (defn __init__ [self &kwargs kwargs]
    (.__init__ (super OP2XH035V1Env self) #**
               (| kwargs {"ace_backend" "xh035-3V3" "ace_variant" 1}))))

(defclass OP2XH035V2Env [OP2Env]
  """
  Implementation: xh035-3V3
  """
  (defn __init__ [self &kwargs kwargs]
    (.__init__ (super OP2XH035V2Env self) #**
               (| kwargs {"ace_backend" "xh035-3V3" "ace_variant" 2}))))

(defclass OP2XH035V3Env [OP2Env]
  """
  Implementation: xh035-3V3
  """
  (defn __init__ [self &kwargs kwargs]
    (.__init__ (super OP2XH035V3Env self) #**
               (| kwargs {"ace_backend" "xh035-3V3" "ace_variant" 3}))))

(defclass OP2XH035V2Env [OP2Env]
  """
  Implementation: xh035-3V3
  """
  (defn __init__ [self &kwargs kwargs]
    (.__init__ (super OP2XH035V2Env self) #**
               (| kwargs {"ace_backend" "xh035-3V3" "ace_variant" 2}))))

(defclass OP2XH018V0Env [OP2Env]
  """
  Implementation: xh018-1V8
  """
  (defn __init__ [self &kwargs kwargs]
    (.__init__ (super OP2XH018V0Env self) #**
               (| kwargs {"ace_backend" "xh018-1V8" "ace_variant" 0}))))

(defclass OP2XH018V1Env [OP2Env]
  """
  Implementation: xh018-1V8
  """
  (defn __init__ [self &kwargs kwargs]
    (.__init__ (super OP2XH018V1Env self) #**
               (| kwargs {"ace_backend" "xh018-1V8" "ace_variant" 1}))))

(defclass OP2XH018V3Env [OP2Env]
  """
  Implementation: xh018-1V8
  """
  (defn __init__ [self &kwargs kwargs]
    (.__init__ (super OP2XH018V3Env self) #**
               (| kwargs {"ace_backend" "xh018-1V8" "ace_variant" 3}))))

(defclass OP2XT018V0Env [OP2Env]
  """
  Implementation: xt018-1V8
  """
  (defn __init__ [self &kwargs kwargs]
    (.__init__ (super OP2XT018V0Env self) #**
               (| kwargs {"ace_backend" "xt018-1V8" "ace_variant" 0}))))

(defclass OP2XT018V1Env [OP2Env]
  """
  Implementation: xt018-1V8
  """
  (defn __init__ [self &kwargs kwargs]
    (.__init__ (super OP2XT018V1Env self) #**
               (| kwargs {"ace_backend" "xt018-1V8" "ace_variant" 1}))))

(defclass OP2XT018V3Env [OP2Env]
  """
  Implementation: xt018-1V8
  """
  (defn __init__ [self &kwargs kwargs]
    (.__init__ (super OP2XT018V3Env self) #**
               (| kwargs {"ace_backend" "xt018-1V8" "ace_variant" 3}))))

(defclass OP2SKY130V0Env [OP2Env]
  """
  Implementation: sky130-1V8
  """
  (defn __init__ [self &kwargs kwargs]
    (.__init__ (super OP2SKY130V0Env self) #**
               (| kwargs {"ace_backend" "sky130-1V8" "ace_variant" 0}))))

(defclass OP2SKY130V1Env [OP2Env]
  """
  Implementation: sky130-1V8
  """
  (defn __init__ [self &kwargs kwargs]
    (.__init__ (super OP2SKY130V1Env self) #**
               (| kwargs {"ace_backend" "sky130-1V8" "ace_variant" 1}))))

(defclass OP2SKY130V3Env [OP2Env]
  """
  Implementation: sky130-1V8
  """
  (defn __init__ [self &kwargs kwargs]
    (.__init__ (super OP2SKY130V3Env self) #**
               (| kwargs {"ace_backend" "sky130-1V8" "ace_variant" 3}))))

(defclass OP2GPDK180V0Env [OP2Env]
  """
  Implementation: gpdk180-1V8
  """
  (defn __init__ [self &kwargs kwargs]
    (.__init__ (super OP2GPDK180V0Env self) #**
               (| kwargs {"ace_backend" "gpdk180-1V8" "ace_variant" 0}))))

(defclass OP2GPDK180V1Env [OP2Env]
  """
  Implementation: gpdk180-1V8
  """
  (defn __init__ [self &kwargs kwargs]
    (.__init__ (super OP2GPDK180V1Env self) #**
               (| kwargs {"ace_backend" "gpdk180-1V8" "ace_variant" 1}))))

(defclass OP2GPDK180V3Env [OP2Env]
  """
  Implementation: gpdk180-1V8
  """
  (defn __init__ [self &kwargs kwargs]
    (.__init__ (super OP2GPDK180V3Env self) #**
               (| kwargs {"ace_backend" "gpdk180-1V8" "ace_variant" 3}))))
