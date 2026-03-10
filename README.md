## Introduction

pals-julia is a parser for the Particle Accelerator Lattice Standard ([PALS](https://github.com/campa-consortium/pals)) for the Julia language. 

## Status

2026-2-24: In initial development.

## Installation

From same root directory, clone [pals-cpp](https://github.com/pals-project/pals-cpp) and [pals-julia](https://github.com/pals-project/pals-julia).  

`src/pals_julia.jl` contains all the functions for manipulating lattice files. It is a
wrapper for the underlying C code contained in `pals-cpp/build/libyaml_c_wrapper.dylib`

For various examples of these functions, see `examples/example.jl`. It can be run with
```console
julia example.jl
```
