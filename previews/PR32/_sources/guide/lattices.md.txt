# Reading and expanding lattices

The `parse_and_expand_pals` entry point reads a PALS lattice
file, resolves any files it includes, and expands the lattice line into an
ordered list of elements. It returns a `Lattices` value with three independent
views of the document:

- **`original`** — the lattice exactly as written in the top-level file.
- **`combined`** — the lattice after its `include`d files have been merged in.
- **`expanded`** — the fully expanded lattice, with lines resolved into a flat
  ordered sequence of elements.

Each view is an ordinary `YAMLNode`, so everything in
[Parsing and writing YAML](parsing.md) applies to it.

## Basic use

```julia
import PALSJulia as pj

lat = pj.parse_and_expand_pals("ex.pals.yaml")

println(pj.to_yaml_string(lat.original))
println(pj.to_yaml_string(lat.combined))
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

## Correspondence between the three views

The `original`, `combined`, and `expanded` trees describe the same lattice at
three stages of processing, so most of their nodes correspond: the constant
`a_const`, for instance, exists in all three. `node_correspondence` builds that
mapping — given any node, it returns the nodes it corresponds to in the other
two views.

```julia
lat  = pj.parse_and_expand_pals("ex.pals.yaml")
corr = pj.node_correspondence(lat)
```

The result is a `Dict` keyed by `YAMLNode`. Looking up a node returns a named
tuple whose fields — `original`, `combined`, `expanded` — are each a
`Vector{YAMLNode}` listing the corresponding nodes in that view:

```julia
a_const = lat.combined["PALS"]["facility"][1]["constants"]["a_const"]

corr[a_const].original   # [ the a_const node in the original tree ]
corr[a_const].expanded   # [ the a_const node in the expanded tree ]
```

The queried node is included in its own view's vector, so the three vectors
together form the complete set of nodes that correspond to one another. You can
look a class up starting from *any* of the three trees and get the same result:

```julia
corr[corr[a_const].original[1]] == corr[a_const]   # true
```

### One-to-many correspondences

Expansion can turn a single node into several — a `repeat` unrolls a line, an
`inherit` copies fields in, a bare element name is substituted with its full
definition, and a fork spawns a new branch. The correspondence follows every
copy, which is why each field is a *vector*: one `combined` node can map to many
`expanded` nodes.

```julia
# The sub-line repeated inside inj_line appears once in `combined`
# but several times in `expanded`.
for (node, class) in corr
    if length(class.combined) == 1 && node == class.combined[1] &&
       length(class.expanded) > 1
        println("combined node → ", length(class.expanded), " expanded copies")
    end
end
```

A vector is empty when a view has no corresponding node. For example, the
`fork_pointer` scalar that expansion synthesises exists only in `expanded`, so
its `original` and `combined` vectors are empty.

!!! note "The mapping is exact, not heuristic"
    The correspondence is not recovered by re-matching the finished trees. The
    three views are built as a derivation chain
    (`original` → `combined` → `expanded`), and the provenance of every node is
    recorded as it is copied. `node_correspondence` reads back that recorded
    provenance, so the mapping is exact even where nodes are duplicated,
    merged, or renamed during expansion.

A runnable version of these examples is in `examples/node_correspondence.jl`.

## Command-line driver

`examples/read_pals.jl` is a small runnable program that wraps the above: it reads
a lattice, expands it, and prints the original, combined, and expanded views. It
accepts a file path and an optional `-lat <name>` flag:

```console
julia examples/read_pals.jl lattice_files/ex.pals.yaml -lat main_ring
```

Place your lattice files under `lattice_files/`.
