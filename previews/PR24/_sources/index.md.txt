# PALSJulia

**PALSJulia** is a Julia parser for the Particle Accelerator Lattice Standard
([PALS](https://github.com/campa-consortium/pals)). It reads PALS-format lattice
files, performs lattice expansion, and translates lattices into
[SciBmad](https://github.com/bmad-sim/SciBmad.jl) and
[Bmad](https://www.classe.cornell.edu/bmad/) formats.

Under the hood, the package is a thin Julia wrapper around the
`yaml_c_wrapper` C library (a [rapidyaml](https://github.com/biojppm/rapidyaml)
backend) shipped with
[pals-cpp](https://github.com/pals-project/pals-cpp). A parsed document is a
tree of `YAMLNode` values that you index and mutate with familiar Julia idioms
(`node["key"]`, `node[i]`, `haskey`, `keys`, `length`, iteration).

```{toctree}
:hidden:
:caption: User Guide

guide/installation
guide/parsing
guide/lattices
guide/translation
```

## What it does

1. **Parse** PALS-format YAML into a `YAMLNode` tree, or build one from
   scratch — see [Parsing and writing YAML](guide/parsing.md).
2. **Expand** a lattice — read a lattice file, resolve its includes, and
   expand the line into an ordered list of elements — see
   [Reading and expanding lattices](guide/lattices.md).
3. **Translate** a PALS lattice to SciBmad or Bmad format — see
   [Translating to SciBmad and Bmad](guide/translation.md).

The complete docstring reference is in the **API Reference** (linked in the
sidebar).

## Quick example

```julia
import PALSJulia as pj

# Read a lattice file and expand it.
lat = pj.parse_and_expand_pals("ex.pals.yaml")

println(pj.to_yaml_string(lat.expanded))   # the expanded lattice as YAML

# Build a document from scratch and write it out.
root = pj.create_empty_tree()
server = pj.add_map!(root; key = "server")
server["host"] = "localhost"
server["port"] = "8080"

pj.write_yaml(root, "config.pals.yaml")
```
