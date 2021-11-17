## Basic Usage

```python
import gym

# Geometric design space and $HOME/.ace symlink or corresponding env vars
env = gym.make('gace:op2-sky130-v1')     # Symmetrical Amplifier in SkyWater 130nm

# Electrical design space and all kwargs
env = gym.make(                      'gace:op2-sky130-v1'    # OP2 in sky130-1V8
              , pdk_path           = '/path/to/tech'         # path to pdk
              , ckt_path           = '/path/to/op2'          # path to testbench
              , nmos_path          = '/path/to/models/nmos'  # path to nmos model
              , pmos_path          = '/path/to/models/pmos'  # path to pmos model
              , max_steps          = 200                     # Reset env after this many steps
              , target             = {}                      # Dict like 'perforamnce' below
              , design-constraints = {}                      # Override default constraints
              , random_target      = False                   # start close to target
              , noisy_target       = False                   # add some noise after each reset
              , data_log_path      = '/path/to/data/log'     # Write data after each episode
              , params_log_path    = '/path/to/param/log'    # Dump circuit state if NaN
              #, reltol             = 1e-3                    # ONLY FOR NAND4 AND ST1
              , )
```

The `design-constraints` dict supports the following fields:

```json
{ "cs":       "Poly Capacitance per μm^2"
, "rs":       "Sheet Resistance in Ω/□ "
, "i0":       "Bias Current in A"
, "vdd":      "Supply Voltage"
, "Wres":     "Resistor Width in m"
, "Mcap":     "Capacitance multiplier"
, "Rc_min":   "Minimum Compensation Resistor = 500Ω"
, "Rc_max":   "Minimum Compensation Resistor = 50000Ω"
, "Cc_min":   "Minimum Compensation Capacitor = 0.5pF"
, "Cc_max":   "Minimum Compensation Capacitor = 5pF"
, "w_min":    "Minimum width either in m or scaled to μm"
, "w_max":    "Maximum width either in m or scaled to μm"
, "l_min":    "Minimum length either in m or scaled to μm"
, "l_max":    "Maximum length either in m or scaled to μm"
, "gmid_min": "Minimum device efficiency"
, "gmid_max": "Maximum device efficiency"
, "fug_min":  "Minimum device speed"
, "fug_max":  "Maximum device speed"
}
```

Other fields should have no effect.