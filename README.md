<h1 align="center">GAC²E</h1>

A collection of [gym](https://gym.openai.com/) environments for analog 
integrated circuit design, based on [AC²E](https://github.com/matthschw/ace) /
[HAC²E](https://github.com/AugustUnderground/hace).

## Installation

```bash
$ pip install git+https://github.com/augustunderground/gace.git
```

Or clone and install a local copy

```bash
$ git clone https://github.com/augustunderground/gace.git
$ pip install .
```

## Requirements

Creating an environment requires trained NMOS and PMOS models and
[HAC²E](https://github.com/AugustUnderground/hace), including all dependencies.

## Getting Started

After installing:

```python
import gym

env = gym.make(                   'gace:op2-xh035-v0'     # Symmetrical Amplifier
              , pdk_path        = '/path/to/tech'         # path to xfab pdk
              , ckt_path        = '/path/to/op2'          # path to testbench
              , nmos_path       = '/path/to/models/nmos'  # path to nmos model
              , pmos_path       = '/path/to/models/pmos'  # paht to pmos model
              , random_target   = False                   # start close to target
              , max_moves       = 200                     # Reset env after this many steps
              , target          = {}                      # Dict like 'perforamnce' below
              , debug_log       = '/path/to/data/log'     # Prefix of data log file
              , )
```

Where `<nmos|pmos>_path` must contain a torchscript model `model.pt` and input
and output scalers `scale.X` and `scale.Y` respectively.

## Single Ended OpAmp Environments

### Observation Space

The observation space includes the current perforamnce, the specified target,
the normalized distance between target and current performance (`| t - p | / t`) 
and operating point characteristics for all devices in the circuit.

#### OP# Environments

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
                 , "A":           "Area" }
, "target":      { "Same keys as 'performance'": "..." }
, "distance":    { "Same keys as 'performance'": "..." }
, "state":       { "electrical characteristics": "..." } }
```

### Reward

The overall reward `r` is calculated based on individual performance
parameters:

```
r = ∑ ( (tanh(| l |) · m) + (- l² · (1 - m)) )
```

Where `l` is the vector with normalized losses for each performance `p` and
target value `t`

```
    | t - p |
l = ---------
        t
```

and `m` is a mask showing whether the performance was reached, i.e. `p > t`, in
which case `tanh` is applied so the reward doesn't increase infinitely.
Otherwise the loss is squared and negated.

### Action Spaces

Action Spaces in `v0` and `v1` are _continuous_ and implemented with
`gym.spaces.Box`. For further details, see the descriptions for specific
environments.

### Variants

| Version | Description                                      |
|---------|--------------------------------------------------|
| `v0`    | Electrical design space (`gmoverid`, `fug`, ...) |
| `v1`    | Geometric Design Space (`W`, `L`, ...)           |
| `v2`    | TBA                                              |

### Technologies

- [X] X-Fab XH035 350nm
- [ ] SkyWater 130nm
- [ ] GPDK 180nm
- [ ] PTM 130nm

### Miller Amplifier (OP1)

![op1](https://github.com/matthschw/ace/blob/main/figures/op1.png)

Registered as `gace:op1-<tech>-<var>`.

#### Action Space 

| Version | Domain               | Description                                                                                                                     |
|---------|----------------------|---------------------------------------------------------------------------------------------------------------------------------|
| `v0`    | `ℝ ¹² ∈ [-1.0; 1.0]` | 4 `gmoverid`s and `fug`s for each building block,<br/> 1 resistance, 1 capacitance and the branch currents <br/> `i1` and `i2`. |
| `v1`    | `ℝ ¹⁴ ∈ [-1.0; 1.0]` | 4 `W`s and `L`s for each building block,<br/> geometric sizes for Rc and Cc as well as <br/> mirror rations `M1` and `M2`.      |

```python
# v0 action space
gym.spaces.Box( low   = -1.0
              , high  = 1.0
              , shape = (12 , )
              , dtype = np.float32
              , )

# v1 action space
gym.spaces.Box( low   = -1.0
              , high  = 1.0
              , shape = (14 , )
              , dtype = np.float32
              , )

```

#### Observation Space

Continuous `ℝ ¹⁵⁰ ∈ (-∞ ; ∞)`:

```python
gym.spaces.Box( low   = -np.inf
              , high  = np.inf
              , shape = (150 , )
              , dtype = np.float32
              , )
```

### Symmetrical Amplifier (OP2)

![op2](https://github.com/matthschw/ace/blob/main/figures/op2.png)

Registered as `gace:op2-<tech>-<var>`.

#### Action Space

| Version | Domain               | Description                                                                               |
|---------|----------------------|-------------------------------------------------------------------------------------------|
| `v0`    | `ℝ ¹⁰ ∈ [-1.0; 1.0]` | 4 `gmoverid`s and `fug`s for each building <br/> block and branch currents `i1` and `i2`. |
| `v1`    | `ℝ ¹² ∈ [-1.0; 1.0]` | 4 `W`s and `L`s for each building block and <br/> mirror ratios `Mcm1` and `Mcm2`.        |

```python
# v0 action space
gym.spaces.Box( low   = -1.0
              , high  = 1.0
              , shape = (10 , )
              , dtype = np.float32
              , )

# v1 action space
gym.spaces.Box( low   = -1.0
              , high  = 1.0
              , shape = (12 , )
              , dtype = np.float32
              , )
```

#### Observation Space

Continuous `ℝ ²⁴⁵ ∈ (-∞ ; ∞)`:

```python
gym.spaces.Box( low   = -np.inf
              , high  = np.inf
              , shape = (245 , )
              , dtype = np.float32
              , )
```

### Un-Symmetrical Amplifier (OP3)

![op3](https://github.com/matthschw/ace/blob/main/figures/op3.png)

Registered as `gace:op3-<tech>-<var>`.

#### Action Space

| Version | Domain               | Description                                                                                                                                            |
|---------|----------------------|--------------------------------------------------------------------------------------------------------------------------------------------------------|
| `v0`    | `ℝ ¹¹ ∈ [-1.0; 1.0]` | Same as _op2_ with an additional branch current. <br/> 4 `gmoverid`s and `fug`s for each building <br/> block and branch currents `i1`, `i2` and `i3`. |
| `v1`    | `ℝ ¹⁵ ∈ [-1.0; 1.0]` | Same as _op2_ with an additional mirror ratio. <br/> 4 `W`s and `L`s for each building block and <br/> mirror ratios `M1` `M2` and `M3`.               |

```python
# v0 action space
gym.spaces.Box( low   = -1.0
              , high  = 1.0
              , shape = (11 , )
              , dtype = np.float32
              , )

# v1 action space
gym.spaces.Box( low   = -1.0
              , high  = 1.0
              , shape = (15 , )
              , dtype = np.float32
              , )
```

#### Observation Space

Same as _op2_, continuous `ℝ ²⁴⁵ ∈ (-∞ ; ∞)`:

```python
gym.spaces.Box( low   = -np.inf
              , high  = np.inf
              , shape = (245 , )
              , dtype = np.float32
              , )
```

### Symmetrical Amplifier with Cascode (OP4)

![op4](https://github.com/matthschw/ace/blob/main/figures/op4.png)

Registered as `gace:op4-<tech>-<var>`.

#### Action Space

| Version | Domain               | Description                                                                                                                 |
|---------|----------------------|-----------------------------------------------------------------------------------------------------------------------------|
| `v0`    | `ℝ ¹⁵ ∈ [-1.0; 1.0]` | 6 `gmoverid`s and `fug`s for each building <br/> block and branch currents `i1`, `i2` and `i3`.                             |
| `v1`    | `ℝ ¹⁸ ∈ [-1.0; 1.0]` | 6 `W`s and `L`s for each building block and <br/> reference transistor, as well as <br/> mirror ratios `M1`, `M2` and `M3`. |

```python
# v0 action space
gym.spaces.Box( low   = -1.0
              , high  = 1.0
              , shape = (15 , )
              , dtype = np.float32
              , )

# v1 action space
gym.spaces.Box( low   = -1.0
              , high  = 1.0
              , shape = (18 , )
              , dtype = np.float32
              , )
```

#### Observation Space

Continuous `ℝ ²⁸⁴ ∈ (-∞ ; ∞)`:

```python
gym.spaces.Box( low   = -np.inf
              , high  = np.inf
              , shape = (284 , )
              , dtype = np.float32
              , )
```

### Un-Symmetrical Amplifier with Cascode (OP5)

<b align="center">UNDER CONSTRUCTION</b>

### Miller Amplifier without R and C (OP6)

![op6](https://github.com/matthschw/ace/blob/main/figures/op6.png)

Registered as `gace:op6-<tech>-<var>`.

#### Action Space

| Version | Domain               | Description                                                                                                                  |
|---------|----------------------|------------------------------------------------------------------------------------------------------------------------------|
| `v0`    | `ℝ ¹⁴ ∈ [-1.0; 1.0]` | 4 `gmoverid`s and `fug`s for each building <br/> block, the weird transistors and the branch <br/> currents `i1` and `i2`.   |
| `v1`    | `ℝ ¹⁸ ∈ [-1.0; 1.0]` | 6 `W`s and `L`s for each building block and <br/> the weird transistors plus the mirror ratios <br/> currents `M1` and `M2`. |

```python
# v0 action space
gym.spaces.Box( low   = -1.0
              , high  = 1.0
              , shape = (14 , )
              , dtype = np.float32
              , )

# v1 action space
gym.spaces.Box( low   = -1.0
              , high  = 1.0
              , shape = (18 , )
              , dtype = np.float32
              , )
```

#### Observation Space

Same as _op1_, continuous `ℝ ¹⁵⁰ ∈ (-∞ ; ∞)`:

```python
gym.spaces.Box( low   = -np.inf
              , high  = np.inf
              , shape = (150 , )
              , dtype = np.float32
              , )
```

## Inverter Environments

### Observation Space

The observation space includes the current perforamnce, the specified target,
the normalized distance between target and current performance (`| t - p | / t`) 
and operating point characteristics for all devices in the circuit.

```json
{ "performance": { "vs0": "Switching Voltage 0"
                 , "vs2": "Switching Voltage 1"
                 , "vs1": "Switching Voltage 2"
                 , "vs3": "Switching Voltage 3" }
, "target":      { "Same keys as 'performance'": "..." }
, "distance":    { "Same keys as 'performance'": "..." }
, "state":       { "electrical characteristics": "..." } }
```

### Reward

The overall reward `r` is calculated based on individual performance
parameters:

```
r = - ∑ ( | t - p | / t )
```

### Action Spaces

Action Spaces in `v1` are _continuous_ and implemented with
`gym.spaces.Box`. For further details, see the descriptions for specific
environments.

### Variations

For now, only `v1` is implemented for Inverter Environments.

### 4 Gate Inverter Chain (NAND4)

![nand4](https://github.com/matthschw/ace/blob/main/figures/nand4.png)

Registered as `gace:nand4-<tech>-<var>`.

#### Action Space

| Version | Domain              | Description                        |
|---------|---------------------|------------------------------------|
| `v1`    | `ℝ ⁵ ∈ [-1.0; 1.0]` | 5 `W`s for each gate in the chain. |

```python
# v1 action space
gym.spaces.Box( low   = -1.0
              , high  = 1.0
              , shape = (5 , )
              , dtype = np.float32
              , )
```

#### Observation Space

Continuous `ℝ ¹² ∈ (-∞ ; ∞)`:

```python
gym.spaces.Box( low   = -np.inf
              , high  = np.inf
              , shape = (12 , )
              , dtype = np.float32
              , )
```

## Schmitt Trigger Environments

### Observation Space

The observation space includes the current perforamnce, the specified target,
the normalized distance between target and current performance (`| t - p | / t`) 
and operating point characteristics for all devices in the circuit.

```json
{ "v_il":  "Threshold Vdd/2 - delta"
, "v_ih":  "Threshold Vdd/2 + delta"
, "t_phl": "Propagation Delay"
, "t_plh": "Propagation Delay" 
, "target":   { "Same keys as 'performance'": "..." }
, "distance": { "Same keys as 'performance'": "..." } }
```

### Reward

The overall reward `r` is calculated based on individual performance
parameters:

```
r = - ∑ ( | t - p | / t )
```

### Action Spaces

Action Spaces in `v1` are _continuous_ and implemented with
`gym.spaces.Box`. For further details, see the descriptions for specific
environments.

### Variations

For now, only `v1` is implemented for Schmitt Trigger Environments.

### Schmitt Trigger (ST1)

![st1](https://github.com/matthschw/ace/blob/main/figures/st1.png)

Registered as `gace:st1-<tech>-<var>`.

#### Action Space

| Version | Domain              | Description                               |
|---------|---------------------|-------------------------------------------|
| `v1`    | `ℝ ⁶ ∈ [-1.0; 1.0]` | 6 `W`s for each device in schmit trigger. |

```python
# v1 action space
gym.spaces.Box( low   = -1.0
              , high  = 1.0
              , shape = (6 , )
              , dtype = np.float32
              , )
```

#### Observation Space

Continuous `ℝ ¹² ∈ (-∞ ; ∞)`:

```python
gym.spaces.Box( low   = -np.inf
              , high  = np.inf
              , shape = (12 , )
              , dtype = np.float32
              , )
```

## Known Issues, Debugging and Testing

Whenever the environment produces observations that contain `NaN` a
`parameters-<timestamp>.json` file will be produced. This can be used with
[HAC²E](https://github.com/AugustUnderground/hace) to load that particular
state and analyze what went wrong.

Currently we cope with `NaN`s by using numpy's 
[nan_to_num](https://numpy.org/doc/stable/reference/generated/numpy.nan_to_num.html) 
function. Be aware, such values can cause problems on GPU.

Test can be run, if [pytest](https://pytest.org) is installed, by calling
`pytest` in the root of this repository, which takes about ~5 min.

```bash
$ pytest
```

## TODO

- [X] fix reward function
- [X] remove target tolerance 
- [X] adjust info key for observations
- [X] set done when met mask true for all
- [X] new Env with geometrical action space
- [X] restructure to fit ace
- [ ] new Env with sim mask as action
- [ ] demo Agent
- [ ] handle `NaN`s better
