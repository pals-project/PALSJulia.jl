## Introduction

`PALSJulia` is a parser for the Particle Accelerator Language Standard ([PALS](https://github.com/campa-consortium/pals)) for the Julia language. 

In addition, `PALSJulia` provides translation functions:

- From `PALS` files to [`Bmad`](https://github.com/bmad-sim/bmad-ecosystem) lattice files.
- From `PALS` files to [`SciBmad`](https://github.com/bmad-sim/SciBmad.jl) lattice files.

For a translator from `Bmad` to `PALS`, the `Bmad` based `Tao` program can be used.
A translator from `SciBmad` to `PALS` is planned.

## Status

- 2026-02-24: In initial development.
- 2026-07-12: Basic lattice translation done.

## Installation

PALSJulia is a thin Julia wrapper around the `yaml_c_wrapper` C library shipped
with [pals-cpp](https://github.com/pals-project/pals-cpp), so both repositories
must be cloned side by side and the C library must be built first.

**See the [Installation guide](https://pals-project.github.io/PALSJulia.jl/guide/installation.html)
for full step-by-step instructions.**

## EXamples

For usage examples, see the runnable scripts in the `examples` directory, e.g.

```console
julia examples/read_pals.jl
```
