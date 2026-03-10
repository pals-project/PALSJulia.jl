## Introduction

Clone [pals-cpp](https://github.com/pals-project/pals-cpp) and [pals-julia](https://github.com/pals-project/pals-julia) in the same directory.  

`src/pals_julia.jl` contains all the functions for manipulating lattice files. It is a
wrapper for the underlying C code contained in `pals-cpp/build/libyaml_c_wrapper.dylib`

For various examples of these functions, see `examples/example.jl`. It can be run with
```console
julia example.jl
```
