## Introduction

PALSJulia is a parser for the Particle Accelerator Lattice Standard ([PALS](https://github.com/campa-consortium/pals)) for the Julia language. 

`get_lattices.jl` is the main program that will read lattices, perform lattice expansion, and print to terminal. See the README for pals-cpp for more information. 

`toSciBmad.jl` translates lattices in PALS format to SciBmad format. Notes on the translation are in `docs/src/guide/translation.md`.

Place lattices files in `/lattice_files`.

## Status

2026-2-24: In initial development.

## Installation

From same root directory, clone [pals-cpp](https://github.com/pals-project/pals-cpp) and [PALSJulia](https://github.com/pals-project/PALSJulia).  

`src/PALSJulia.jl` contains all the functions for manipulating lattice files. It is a
wrapper for the underlying C code contained in `pals-cpp/build/libyaml_c_wrapper.dylib`

For various examples of these functions, see the examples in the `examples` directory. 
It can be run with
```console
julia example.jl
```
