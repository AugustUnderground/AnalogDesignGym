# Analog Design Gym

[gym](https://gym.openai.com/) environments for analog integrated circuit
design, based on [AC²E](https://github.com/mattschw/ace) /
[HAC²E](https://github.com/AugustUnderground/hace).

## Installation

```bash
$ pip install git+https://github.com/augustunderground/gym-analog-design.git
```

## Requirements

Creating an environment requires trained NMOS and PMOS models and HAC²E
including all dependencies.

## Getting Started

After installing:

```python
import gym

env = gym.make( 'gym_ad:op2-xh035-v0'               # Only working env right now
              , pdk-path  = '/path/to/tech'         # path to xfab pdk
              , ckt-path  = '/path/to/op2'          # path to testbench
              , nmos-path = '/path/to/models/nmos'  # path to nmos model
              , pmos-path = '/path/to/models/pmos'  # paht to pmos model
              , random-target = False )             # start close to target
```

Where `<nmos|pmos>_path` is the location of the corresponding `model.pt`.

## Environments

### Observation Space

All Amplifier environments share the same kind of observations, which is a
concatenations of targets, performances, distance between target and
performance as well as the current sizing and characteristics of individual
devices.

```json
{ "performance": { "a_0":         "DC Gain"
                 , "ugbw":        "Unity Gain Bandwidth"
                 , "pm":          "Phase Margin"
                 , "gm":          "Gain Margin"
                 , "sr_r":        "Slew Rate rising"
                 , "sr_f":        "Slew Rate falling"
                 , "vn_1Hz":      "Output-referred noise density @ 1Hz"
                 , "vn_10Hz":     "Output-referred noise density @ 10Hz"
                 , "vn_100Hz":    "Output-referred noise density @ 100Hz"
                 , "vn_1kHz":     "Output-referred noise density @ 1kHz"
                 , "vn_10kHz":    "Output-referred noise density @ 10kHz"
                 , "vn_100kHz":   "Output-referred noise density @ 100kHz"
                 , "psrr_p":      "Power Supply Rejection Ratio"
                 , "psrr_n":      "Power Supply Rejection Ratio"
                 , "cmrr":        "Common Mode Rejection Ratio"
                 , "v_il":        "Input Low"
                 , "v_ih":        "Input High"
                 , "v_ol":        "Output Low"
                 , "v_oh":        "Output High"
                 , "i_out_min":   "Minimum output current"
                 , "i_out_max":   "Maximum output current"
                 , "overshoot_r": "Slew rate overswing rising"
                 , "overshoot_f": "Slew rate overswing falling"
                 , "voff_stat":   "Statistical Offset"
                 , "voff_sys":    "Systematic Offset"
                 , "A"            "Area" }
, "target":      {"Same keys as 'performance'": ... }
, "distance":    {"Same keys as 'performance'": ...}
, "state":       {"electrical characteristics": ...} }
```

Where the `performance` are the simulation / analyses results and `distance` is
the normalized error `| target - performance | / target`.

### Miller Amplifier (OP1)

![op1](https://github.com/matthschw/ace/blob/main/figures/op1.png)

Registered as `gym_ad:op1-xh035-v0`.

#### Action Space

4 `gmoverid`s and `fug`s for each building block, 1 resistance, 1 capacitance
and the branch currents `i1` and `i2`. 
`(, 12) ∈ [-1.0; 1.0]` in total.

### Symmetrical Amplifier (OP2)

![op2](https://github.com/matthschw/ace/blob/main/figures/op2.png)

Registered as `gym_ad:op2-xh035-v0`.

#### Action Space

4 `gmoverid`s and `fug`s for each building block and branch currents `i1` and
`i2` `(, 10) ∈ [-1.0; 1.0]` in total. De-normalization and scaling is
handled in the environment. For a new technology, a new class should be
derived.

### Un-Symmetrical Amplifier (OP3)

![op3](https://github.com/matthschw/ace/blob/main/figures/op3.png)

Registered as `gym_ad:op3-xh035-v0`.

#### Action Space

4 `gmoverid`s and `fug`s for each building block and branch current `i1`, `i2`
and `i3`. `(, 11) ∈ [-1.0; 1.0]` in total. De-normalization and scaling is
handled in the environment. For a new technology, a new class should be
derived.

### Symmetrical Amplifier with Cascode (OP4)

![op4](https://github.com/matthschw/ace/blob/main/figures/op4.png)

Registered as `gym_ad:op4-xh035-v0`.

#### Action Space

6 `gmoverid`s and `fug`s for each building block and branch current `i1`, `i2`
and `i3`. `(, 15) ∈ [-1.0; 1.0]` in total. De-normalization and scaling is
handled in the environment. For a new technology, a new class should be
derived.

### ... (OP5)

**UNDER CONSTRUCTION**

### Miller Amplifier without R and C (OP6)

![op6](https://github.com/matthschw/ace/blob/main/figures/op6.png)

Registered as `gym_ad:op6-xh035-v0`.

#### Action Space

4 `gmoverid`s and `fug`s for each building block, the weird transistors
and the branch currents `i1` and `i2`. 
`(, 14) ∈ [-1.0; 1.0]` in total.

## TODO

- [ ] Fix reward function
- [X] remove target tolerance 
- [X] adjust info key for observations
- [X] set done when met mask true for all
- [ ] new env with sim mask as action
