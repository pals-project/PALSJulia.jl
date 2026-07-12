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

### Jupyter notebooks (IJulia)

Some examples are also provided as Jupyter notebooks (e.g.
`examples/manipulate_tree.ipynb`). To run them you need
[IJulia](https://github.com/JuliaLang/IJulia.jl), the Julia kernel for Jupyter.

Install IJulia once:

```console
julia -e 'using Pkg; Pkg.add("IJulia")'
```

Then launch Jupyter directly from Julia — IJulia bundles its own Jupyter, so no
separate system install is needed (the first launch will offer to install it):

```julia
using IJulia
notebook(dir="examples")
```

This opens Jupyter in your browser; from there open `manipulate_tree.ipynb`.

If you prefer a system-wide `jupyter` command instead, install it with
`pip install jupyter`; adding IJulia as above then registers the Julia kernel
with it, and you can run:

```console
jupyter notebook examples/manipulate_tree.ipynb
```
