# Reading and expanding lattices

The `parse_and_expand_pals` entry point reads a PALS lattice
file, resolves any files it includes, and expands the lattice line into an
ordered list of elements. It returns a `Lattices` value with three independent
views of the document:

- **`original`** — the lattice exactly as written in the top-level file.
- **`included`** — the lattice after its `include`d files have been merged in.
- **`expanded`** — the fully expanded lattice, with lines resolved into a flat
  ordered sequence of elements.

Each view is an ordinary `YAMLNode`, so everything in
[Parsing and writing YAML](parsing.md) applies to it.

## Basic use

```julia
import PALSJulia as pj

lat = pj.parse_and_expand_pals("ex.pals.yaml")

println(pj.to_yaml_string(lat.original))
println(pj.to_yaml_string(lat.included))
println(pj.to_yaml_string(lat.expanded))
```

To expand a single named lattice from a file that defines several, pass its
name as the second argument:

```julia
lat = pj.parse_and_expand_pals("ex.pals.yaml", "main_ring")
```

## Relative includes

Include paths inside a lattice file are resolved relative to the working
directory when the C library opens them. If your lattice `include`s other files
by relative path, `cd` into the lattice directory first:

```julia
lattice_dir = joinpath(@__DIR__, "..", "lattice_files")

lat = cd(lattice_dir) do
    pj.parse_and_expand_pals("ex.pals.yaml")
end
```

## Command-line driver

`examples/read_pals.jl` is a small runnable program that wraps the above: it reads
a lattice, expands it, and prints the original, included, and expanded views. It
accepts a file path and an optional `-lat <name>` flag:

```console
julia examples/read_pals.jl lattice_files/ex.pals.yaml -lat main_ring
```

Place your lattice files under `lattice_files/`.
