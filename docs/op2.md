### Symmetrical Amplifier (OP2)

![op2](https://github.com/matthschw/ace/blob/main/figures/op2.png)

Registered as `gace:op2-<tech>-<variant>`.

#### Observation Space

| Technology | Dimensions         |
|------------|--------------------|
| `xh035`    | `ℝ ²⁰⁶ ∈ (-∞ ; ∞)` |
| `sky130`   | `ℝ ²⁶⁶ ∈ (-∞ ; ∞)` |
| `gpdk180`  | `ℝ ²⁹⁴ ∈ (-∞ ; ∞)` |

```python
# xh035
gym.spaces.Box( low   = -np.inf
              , high  = np.inf
              , shape = (206 , )
              , dtype = np.float32
              , )

# sky130
gym.spaces.Box( low   = -np.inf
              , high  = np.inf
              , shape = (266 , )
              , dtype = np.float32
              , )

# gpdk180
gym.spaces.Box( low   = -np.inf
              , high  = np.inf
              , shape = (294 , )
              , dtype = np.float32
              , )
```

#### Action Space

<table>
<tr><th>Variant</th><th>Dimensions</th> <th>Parameters</th></tr>
<tr> 
<td> 

`v0` 

</td> 
<td> 

`ℝ ¹⁰ ∈ [-1.0; 1.0]`

</td>
<td>

```python
[ "gmid-cm1", "gmid-cm2", "gmid-cm3", "gmid-d"
, "fug-cm1",  "fug-cm2",  "fug-cm3",  "fug-d" 
, "i1" "i2" ]
```

</td>
</tr>
<tr> 
<td> 

`v1` 

</td> 
<td> 

`ℝ ¹² ∈ [-1.0; 1.0]`

</td>
<td>

```python
[ "Ld", "Lcm1",  "Lcm2", "Lcm3"  
, "Wd", "Wcm1",  "Wcm2", "Wcm3" 
      , "Mcm11", "Mcm21"  
      , "Mcm12", "Mcm22"           ]
```

</td>
</tr>
</table>

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


