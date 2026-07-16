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

## Matching constructs by name

Once a lattice is expanded, `match_names` finds every named construct that a
PALS *Name Matching* string refers to — elements, parameter groups, parameters,
constants, and variables — and returns them as a `Vector{YAMLNode}`. The syntax
is:

```text
[{lattice}>>>][{branch}>>][{kind}::]{name}[>{group}.{subgroup}. … .{parameter}]
```

`{lattice}`, `{branch}`, and `{name}` are [PCRE2](https://www.pcre.org) patterns
matched against the *whole* name (anchored at both ends), so `B1.*` matches `B1a`
and `B1b` but `B1` on its own matches neither. `{kind}` is matched exactly, and
the dotted parameter path after the single `>` is matched exactly, key by key.
An omitted or empty pattern matches every name at that level, and `{branch}`
matches an element if any enclosing BeamLine/Branch name matches — so elements in
sub-lines are included.

```julia
lat = pj.parse_and_expand_pals("ex.pals.yaml")

# The `e1` bend parameter of every element whose name begins with `B1`:
pj.match_names(lat.expanded, "B1.*>BendP.e1")

# Restrict to an element kind with `::`:
pj.match_names(lat.expanded, "Quadrupole::.*>length")

# Restrict to a named beamline/branch (`>>`) or lattice (`>>>`):
pj.match_names(lat.expanded, "inj_line>>Q.*>length")
pj.match_names(lat.expanded, "ring>>>inj_line>>Q.*>length")

# Omit the parameter path to match the element itself, or the group:
pj.match_names(lat.expanded, "Q1a")             # the element node
pj.match_names(lat.expanded, "Q1a>BendP")       # a parameter-group node
```

Pass any node of the tree you want to search — normally `lat.expanded`, since
beamlines and elements are only fully realised after expansion. The returned
nodes belong to that same tree, so you can read or modify them in place:

```julia
for n in pj.match_names(lat.expanded, "B1.*>BendP.e1")
    pj.set_scalar!(n, "0.0")   # zero the entrance-face angle of each B1… bend
end
```

### Constants and variables

Lattice parameters include constant and variable names. A *bare* name — no
lattice/branch/kind qualifier and no parameter path — also matches every
constant and variable defined directly under the `PALS` or `facility` node, in
both the full (`kind: constant` / `kind: variable`) and compact
(`constants:` / `variables:` list) forms:

```julia
pj.match_names(lat.expanded, "a_const")   # one named constant
pj.match_names(lat.expanded, "a_.*")      # every constant/var named a_…
```

For a compact-form entry the matched node is the `name: value` scalar; for a
full-form entry it is the named node, underneath which `kind`/`value` live.

!!! note "Not yet implemented"
    The full *Element Name Matching* grammar also defines `#N` instance
    selection, `{e1}:{e2}` ranges, `,` unions, and `&` intersections. These are
    not yet handled by `match_names`.

Results are de-duplicated and returned in document order, and a malformed
pattern yields an empty vector. A runnable version of these examples is in
`examples/match_names.jl`.

## Command-line driver

`examples/read_pals.jl` is a small runnable program that wraps the above: it reads
a lattice, expands it, and prints the original, combined, and expanded views. It
accepts a file path and an optional `-lat <name>` flag:

```console
julia examples/read_pals.jl lattice_files/ex.pals.yaml -lat main_ring
```

Place your lattice files under `lattice_files/`.
