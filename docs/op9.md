### WORK IN PROGRESS (OP9)

![op9](https://raw.githubusercontent.com/matthschw/ace/main/figures/op9.png)

_Will be_ registered as `gace:op9-<tech>-<variant>`.

#### Observation Space

| Technology | Dimensions         |
|------------|--------------------|
| `xh035`    | `ℝ ³⁷¹ ∈ (-∞ ; ∞)` |

```python
# xh035
gym.spaces.Box( low   = -np.inf
              , high  = np.inf
              , shape = (371 , )
              , dtype = np.float32
              , )
```

#### Action Space

| Variant | Dimensions           | Parameters                                                                                                                                                                                                                    |
|---------|----------------------|-------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| `v0`    | `ℝ ²² ∈ [-1.0; 1.0]` | `["gmid-d1", "gmid-cm1", "gmid-cm2", "gmid-cm3", "gmid-cm4", "gmid-ls1", "gmid-r1", "gmid-r2", "fug-d1", "fug-cm1", "fug-cm2", "fug-cm3", "fug-cm4", "fug-ls1", "fug-r1", "fug-r2", "i1", "i2", "i3", "i4", "i5", "i6"]`      |
| `v1`    | `ℝ ²⁷ ∈ [-1.0; 1.0]` | `["Ld1", "Lcm1", "Lcm2", "Lcm3", "Lcm4", "Lls1", "Lr1", "Lr2", "Wd1", "Wcm1", "Wcm2", "Wcm3", "Wcm4", "Wls1", "Wr2", "Wr1", "Mcm1", "Mcm2", "Mcm31", "Mcm41", "Mls1", "Mcm32", "Mcm42", "Mcm33", "Mcm43", "Mcm34", "Mcm44"]` |

```python
# v0 action space
gym.spaces.Box( low   = -1.0
              , high  = 1.0
              , shape = (22 , )
              , dtype = np.float32
              , )

# v1 action space
gym.spaces.Box( low   = -1.0
              , high  = 1.0
              , shape = (27 , )
              , dtype = np.float32
              , )
```

