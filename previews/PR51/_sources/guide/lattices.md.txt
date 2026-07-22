# Reading and expanding lattices

The `parse_and_expand_pals` entry point reads a PALS lattice
file, resolves any files it includes, and expands the lattice line into an
ordered list of elements. It returns a `Lattices` value with four independent
views of the document:

- **`original`** — the lattice exactly as written in the top-level file.
- **`combined`** — the lattice after its `include`d files have been merged in.
- **`expanded`** — the fully expanded root lattice, with lines resolved into a
  flat ordered sequence of elements, and nothing else.
- **`leftover`** — everything else the document contained.

Each view is an ordinary `YAMLNode`, so everything in
[Parsing and writing YAML](parsing.md) applies to it.

## `expanded` and `leftover`

Expansion picks one lattice — the root lattice — and resolves it. `expanded`
holds *only* that result, and it is rooted at the lattice entry itself, without
the `PALS:`/`facility:` scaffolding the lattice was written under:

```yaml
lat1:
  kind: Lattice
  branches:
    - main_line:
        ...
```

so the lattice is reached as `lat.expanded["lat1"]`, not through
`["PALS"]["facility"]`.

Everything the root lattice did not absorb stays in `leftover`, which *does*
keep the full `PALS:`/`facility:` document: element and beamline definitions,
`use` statements, constants and variables, `Controller`s, and any `Lattice`
other than the one expanded. Definitions that expansion substituted into the
lattice are copied rather than moved, so they appear in both views — the
definition in `leftover`, its inlined copy in `expanded`.

## Basic use

```julia
import PALSJulia as pj

lat = pj.parse_and_expand_pals("ex.pals.yaml")

println(pj.to_yaml_string(lat.original))
println(pj.to_yaml_string(lat.combined))
println(pj.to_yaml_string(lat.expanded))
println(pj.to_yaml_string(lat.leftover))
```

To expand a single named lattice from a file that defines several, pass its
name as the second argument:

```julia
lat = pj.parse_and_expand_pals("ex.pals.yaml", "main_ring")
```

## Reporting problems

Expanding a lattice can hit problems that are not fatal but are worth knowing
about: a `line` that references an element which was never defined, an
`inherit`/`repeat`/`Fork` whose target is missing, or an expression that could
not be evaluated (an unknown constant, a dangling element‑parameter reference, a
dependency cycle). Rather than abort, expansion keeps going — leaving the
offending value as text — and collects a list of every such problem.

The `problems` keyword controls what is done with that list:

```julia
# Default: print the problems to stderr (nothing prints when there are none).
lat = pj.parse_and_expand_pals("ex.pals.yaml")

# Write the problems to a file instead, printing nothing.
lat = pj.parse_and_expand_pals("ex.pals.yaml"; problems = "problems.txt")

# Say nothing at all.
lat = pj.parse_and_expand_pals("ex.pals.yaml"; problems = :none)
```

A typical report looks like:

```
parse_and_expand_pals: 2 problem(s) encountered during lattice expansion:
  - reference to undefined element or line 'NoSuchElement'
  - could not evaluate expression for BendP.edge_int2: 0.02 * thingB>MagneticMultipoleP.NotThere
```

Only values that look like expressions (an operator, a parenthesis, an
element‑parameter `>` reference, or an explicit `expr(...)`) are flagged when
they fail to evaluate; a plain name, label, or boolean that happens not to be a
number is left alone.

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

## Correspondence between the views

The four trees describe the same lattice at successive stages of processing, so
most of their nodes correspond: the constant `a_const`, for instance, exists in
`original`, in `combined`, and — since it is not part of the lattice — in
`leftover`. `node_correspondence` builds that mapping: given any node, it returns
the nodes it corresponds to in the other views.

```julia
lat  = pj.parse_and_expand_pals("ex.pals.yaml")
corr = pj.node_correspondence(lat)
```

The result is a `Dict` keyed by `YAMLNode`. Looking up a node returns a named
tuple whose fields — `original`, `combined`, `expanded`, `leftover` — are each a
`Vector{YAMLNode}` listing the corresponding nodes in that view:

```julia
a_const = lat.combined["PALS"]["facility"][1]["constants"]["a_const"]

corr[a_const].original   # [ the a_const node in the original tree ]
corr[a_const].leftover   # [ the a_const node in the leftover tree ]
corr[a_const].expanded   # [] — the lattice never referenced it
```

The queried node is included in its own view's vector, so the four vectors
together form the complete set of nodes that correspond to one another. You can
look a class up starting from *any* of the four trees and get the same result:

```julia
corr[corr[a_const].original[1]] == corr[a_const]   # true
```

Because expansion splits the document, a `combined` node can reach `expanded`,
`leftover`, or both. A beamline named by the root lattice is a good example: its
definition stays in `leftover` while a copy of it is inlined into `expanded`, and
both belong to the same class.

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
its `original` and `combined` vectors are empty; a constant the lattice never
refers to exists only in `leftover`, so its `expanded` vector is empty.

!!! note "The mapping is exact, not heuristic"
    The correspondence is not recovered by re-matching the finished trees. The
    views are built as a derivation chain (`original` → `combined` →
    `expanded` and `leftover`), and the provenance of every node is
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

Pass any node of the tree you want to search — `lat.expanded` for beamlines and
elements, since those are only fully realised after expansion. The returned
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

Constants and variables are defined at facility level rather than inside the
lattice, so they are found in `lat.leftover` — searching `lat.expanded` for one
matches nothing, as the `PALS`/`facility` node it lives under is not part of
that tree:

```julia
pj.match_names(lat.leftover, "a_const")   # one named constant
pj.match_names(lat.leftover, "a_.*")      # every constant/var named a_…
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

## Reading a parameter value

Where `match_names` returns the *nodes* a string refers to, `parameter_value`
returns the single *value* a parameter holds. It takes the whole expanded lattice
`lat` and the same *Name Matching* syntax, and returns a `Float64`, a `String`, or
`missing`. Like `match_names`, the string names either an element parameter (with
a parameter path) or, as a *bare* name, a constant or variable:

```julia
lat = pj.parse_and_expand_pals("ex.pals.yaml")

pj.parameter_value(lat, "lat1>>>B1a>BendP.e1")        # 0.1     (element param, from expanded)
pj.parameter_value(lat, "F1>ReferenceP.species_ref")  # "#3He"  (a string)
pj.parameter_value(lat, "Q1>BendP.g")                 # 0.0     (unset → default)
pj.parameter_value(lat, "Q1")                         # missing (an element is not a value)
pj.parameter_value(lat, "a_const")                    # a constant (from leftover)
```

`parameter_value` searches only two of `lat`'s four views: `lat.expanded`, which
holds the element parameters, and then, if the name is not found there,
`lat.leftover`, which holds the facility-level constants, variables, and any
definitions not spliced into the lattice. The raw `lat.original` and
`lat.combined` views are **not** searched.

Because both searched views are post-expansion, values come back already
evaluated — a numeric value as a `Float64`, and a non-numeric one (a species name,
or an expression expansion left unevaluated such as one using `random()`) verbatim
as a `String`:

- **Element parameter, set** — its value: a `Float64`, or a `String` when
  non-numeric.
- **Element parameter, unset** — an element that exists but does not set the
  parameter yields the parameter's default. That default is `0.0` for every
  parameter for now; real per-parameter defaults come later.
- **Constant or variable** — a bare name yields its value, the same way.
- **Unidentified** — `missing`, when the name matches nothing in either view, is a
  bare element (an element has no single scalar value), stops on a whole parameter
  group rather than a single value, or several matches disagree on the value.
  (Matches that *agree* — the same element reused, or several that all take the
  default — collapse to the one shared value.)

!!! note "Defaults are provisional"
    Because there is no parameter schema yet, an unset parameter and a name that
    is not a real parameter are indistinguishable, so both return the `0.0`
    default rather than `missing`. When defaults arrive, an unknown parameter
    name will return `missing` instead.

## Command-line driver

`examples/read_pals.jl` is a small runnable program that wraps the above: it reads
a lattice, expands it, and prints the original, combined, and expanded views. It
accepts a file path and an optional `-lat <name>` flag:

```console
julia examples/read_pals.jl lattice_files/ex.pals.yaml -lat main_ring
```

Place your lattice files under `lattice_files/`.
