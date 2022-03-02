### Symmetrical Amplifier (OP2)

![op2](https://raw.githubusercontent.com/matthschw/ace/main/figures/op2.png)

Registered as `gace:op2-<tech>-<variant>`.

#### Observation Space

| Technology | Dimensions     |
|------------|----------------|
| `xh035`    | `ℝ²¹⁴∈(-∞ ;∞)` |
| `xh018`    | `ℝ²¹⁴∈(-∞ ;∞)` |
| `xt018`    | `ℝ²¹⁴∈(-∞ ;∞)` |
| `sky130`   | `ℝ²⁷⁴∈(-∞ ;∞)` |
| `gpdk180`  | `ℝ³¹⁴∈(-∞ ;∞)` |

For details see the `output-parameters` field of the `info` dictionary
returned by `step()`.

```python
# xh035
gym.spaces.Box( low   = -np.inf
              , high  = np.inf
              , shape = (214 , )
              , dtype = np.float32
              , )

# sky130
gym.spaces.Box( low   = -np.inf
              , high  = np.inf
              , shape = (274 , )
              , dtype = np.float32
              , )

# gpdk180
gym.spaces.Box( low   = -np.inf
              , high  = np.inf
              , shape = (314 , )
              , dtype = np.float32
              , )
```

#### Action Space

| Variant | Dimensions       | Parameters                                                                                            |
|---------|------------------|-------------------------------------------------------------------------------------------------------|
| `v0`    | `ℝ¹⁰∈[-1.0;1.0]` | `["gmid-cm1", "gmid-cm2", "gmid-cm3", "gmid-d", "fug-cm1", "fug-cm2", "fug-cm3", "fug-d", "i1" "i2"]` |
| `v1`    | `ℝ¹²∈[-1.0;1.0]` | `["Ld", "Lcm1", "Lcm2", "Lcm3", "Wd", "Wcm1", "Wcm2", "Wcm3", "Mcm11", "Mcm21", "Mcm12", "Mcm22"]`    |
| `v2`    | `ℝ¹⁰∈[0,1,2]`    | `["gmid-cm1", "gmid-cm2", "gmid-cm3", "gmid-d", "fug-cm1", "fug-cm2", "fug-cm3", "fug-d", "i1" "i2"]` |
| `v3`    | `ℝ¹²∈[0,1,2]`    | `["Ld", "Lcm1", "Lcm2", "Lcm3", "Wd", "Wcm1", "Wcm2", "Wcm3", "Mcm11", "Mcm21", "Mcm12", "Mcm22"]`    |

Where `i1` is the drain current through `MNCM12` and `i2` is the drain current
through `MPCM212` and `MPCM222`.

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

# v2 action space
gym.spaces.MultiDiscrete( list(repeat(3, 10))
                        , dtype = np.int32
                        , )

# v3 action space
gym.spaces.MultiDiscrete( list(repeat(3, 12))
                        , dtype = np.int32
                        , )
```

