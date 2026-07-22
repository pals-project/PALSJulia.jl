# ─── internal helpers ────────────────────────────────────────────────────────

# Wrap a tree handle and return a node pointing to its root.
function _root_node(handle::Ptr{Cvoid})
  tree    = YAMLTree(handle)
  root_id = @ccall (libyaml()).get_root(handle::Ptr{Cvoid})::Csize_t
  return YAMLNode(tree, root_id)
end

# The root of the tree `node` belongs to (`node` itself if it is the root).
# Unlike _root_node, this shares the existing YAMLTree instead of taking
# ownership of the handle.
function _tree_root(node::YAMLNode)
  root_id = @ccall (libyaml()).get_root(node.tree.handle::Ptr{Cvoid})::Csize_t
  return YAMLNode(node.tree, root_id)
end

# The most recent parse error recorded by the C library on this thread (empty
# when the last parse succeeded). Used to append a location — "line L, column C"
# — to the error PALSJulia raises when a parse fails, so the offending line is
# pinpointed instead of reporting a bare failure.
function _last_parse_error()
  ptr = @ccall (libyaml()).yaml_last_parse_error()::Cstring
  ptr == C_NULL ? "" : unsafe_string(ptr)
end

# ─── parse_and_expand_pals ────────────────────────────────────────────────────

# Copy the C-owned problem strings into a Julia Vector{String} and free the
# underlying C array. Always frees, even when the list is empty.
function _take_problem_list(sl::StringListC)
  n = Int(sl.count)
  out = Vector{String}(undef, n)
  if n > 0
    ptrs = unsafe_wrap(Array, sl.items, n)
    for i in 1:n
      out[i] = unsafe_string(ptrs[i])
    end
  end
  @ccall (libyaml()).free_lattice_problems(sl::StringListC)::Cvoid
  return out
end

# Apply the `problems` output policy: `:print` (default) writes to stderr,
# a filename string writes to that file, `:none` does nothing.
function _report_problems(problems::Vector{String}, mode)
  if mode isa AbstractString
    open(mode, "w") do io
      if isempty(problems)
        println(io, "No problems encountered during lattice expansion.")
      else
        println(io, "$(length(problems)) problem(s) encountered during lattice expansion:")
        for p in problems
          println(io, "  - ", p)
        end
      end
    end
  elseif mode === :none
    # do nothing
  else  # :print
    if !isempty(problems)
      println(stderr, "parse_and_expand_pals: $(length(problems)) problem(s) encountered during lattice expansion:")
      for p in problems
        println(stderr, "  - ", p)
      end
    end
  end
  return nothing
end

"""
    parse_and_expand_pals(filename, root_lattice=""; problems=:print) -> Lattices

Parse a PALS lattice file and return its `original`, `combined`, `expanded` and
`leftover` views, together with the list of expansion `problems`, as a
[`Lattices`](@ref).

# Arguments
- `filename`: Path to the top-level YAML lattice file.
- `root_lattice`: Name of the lattice to expand. If empty (the default), the
  lattice to expand is chosen with the following priority:
    1. the lattice named by the last `use` statement, or
    2. the last lattice defined in the file if no `use` statement is present.
- `problems`: What to do with the list of problems found while expanding
  (undefined lattice, dangling element/line references, undefined
  `inherit`/`repeat`/`Fork` targets, and expressions that could not be
  evaluated). One of:
    - `:print` (the default) — print the problems to `stderr` (nothing is
      printed when there are none);
    - a filename `String` — write the problems to that file, printing nothing;
    - `:none` — do nothing (no printing, no file).

# Returns
A `Lattices` with four independent tree views and a `problems` list. The same
problems handed to `problems` are also returned in the `problems` field
(a `Vector{String}`, empty when expansion was clean) regardless of the reporting
mode, so `:none` still lets the caller inspect them programmatically.

The four tree views are:
- `original`: the tree as read in, mapping each file (including any `include`d
  files) to its unparsed contents.
- `combined`: the tree with all `include` directives resolved and spliced
  inline.
- `expanded`: the selected lattice fully expanded, and nothing else — scalars
  substituted with their full definitions, `repeat`ed beamlines unrolled,
  `inherit`ed ancestors merged in, and forks resolved. It is rooted at a map
  holding the single `name => Lattice` entry, without the `PALS`/`facility`
  scaffolding the lattice was defined under, so the lattice is reached as
  `lat.expanded["lat1"]` rather than through `["PALS"]["facility"]`. Its
  `branches` entries are branches, not the `BeamLine`s they were built from, and
  so carry no `kind`; a `BeamLine` referenced inside a `line` is a sub-line whose
  contents are spliced directly into the enclosing line, so no nested `BeamLine`
  survives in the expanded tree. Elements of a `multipass` line carry a
  `multipass_index` giving their 1-based position within that line's expansion
  (the nearest enclosing `multipass` line wins when they nest).
- `leftover`: everything the `expanded` tree does not carry, keeping its
  `PALS`/`facility` scaffolding: element and beamline definitions, `use`
  statements, constants and variables, `Controller`s, and any `Lattice` that
  was not the one expanded. A definition that expansion substituted into the
  lattice is *copied*, so it appears in both trees.

Every mathematical expression is evaluated to a number across both `expanded`
and `leftover` (see [`evaluate_pals_expression`](@ref);
`random()`/`random_gauss()` are left as text). `Controller` elements are
evaluated against their own scoped variable tables, with each control
`expression` computed and stored back in its control entry; controllers are
facility-level, so they are found in `leftover`.

Each view is backed by its own `YAMLNode`; all four are freed independently
when their nodes are garbage collected.
"""
function parse_and_expand_pals(filename::String, root_lattice::String="";
                               problems::Union{Symbol,AbstractString}=:print)
  isfile(filename) || error("File not found: $filename")
  (problems isa AbstractString || problems === :print || problems === :none) ||
    throw(ArgumentError("`problems` must be :print, :none, or a filename string"))

  handles = @ccall (libyaml()).parse_and_expand_PALS(
    filename::Cstring,
    root_lattice::Cstring
  )::LatticesHandle

  # Take ownership of the problem list before anything can error out.
  problem_list = _take_problem_list(handles.problems)

  # NULL handles mean a fatal parse failure (a malformed top-level file): there
  # is no tree to expand. The C library reports why — with the offending
  # line/column — as the single problem, so surface that rather than a bare
  # failure. This raises a normal Julia error; it does not abort the process.
  if handles.original == C_NULL || handles.combined == C_NULL ||
     handles.expanded == C_NULL || handles.leftover == C_NULL
    detail = isempty(problem_list) ? "" : "\n  " * join(problem_list, "\n  ")
    error("Failed to parse lattice file: $filename$detail")
  end

  _report_problems(problem_list, problems)

  return Lattices(
    _root_node(handles.original),
    _root_node(handles.combined),
    _root_node(handles.expanded),
    _root_node(handles.leftover),
    problem_list,
  )
end

# ─── expression evaluation ────────────────────────────────────────────────────

"""
    evaluate_pals_expression(expr::AbstractString) -> Float64

Evaluate a single PALS mathematical expression to a `Float64`.

Supports the full PALS expression grammar: arithmetic (`+ - * / ^`), unary
signs, parentheses, the built-in constants (`pi`, `c_light`, `r_electron`, …),
the math functions (`sqrt`, `log`, `sin`, `floor`, `modulo`, …), and the
particle-data functions `mass_of`, `charge_of`, and `anomalous_moment_of`
(backed by AtomicAndPhysicalConstantsCLib), whose species-name argument must be
quoted, e.g. `mass_of("#3He")` (a mass number carries a leading `#`). A leading
`expr(...)` wrapper is accepted and unwrapped.

This evaluates a standalone string, so user-defined constants and variables are
**not** in scope — use [`parse_and_expand_pals`](@ref) for whole-lattice
evaluation, whose `expanded` tree already has every expression resolved to a
number. Throws `ArgumentError` if `expr` is not evaluable: a parse error, an
unknown identifier or species, a `random()`/`random_gauss()` expression (which
is intentionally deferred), or a non-finite result.

# Example
```julia
evaluate_pals_expression("3.75e7 / c_light^2")   # 4.172…e-10
evaluate_pals_expression("mass_of(\"electron\")") # 510998.95069…
evaluate_pals_expression("expr(2 * pi)")         # 6.283…
```
"""
function evaluate_pals_expression(expr::AbstractString)
  ok = Ref{Bool}(false)
  val = @ccall (libyaml()).evaluate_pals_expression(
    String(expr)::Cstring, ok::Ref{Bool})::Cdouble
  ok[] || throw(ArgumentError("Not an evaluable PALS expression: \"$expr\""))
  return val
end

# ─── node correspondence ──────────────────────────────────────────────────────

# Concrete value type stored in the correspondence Dict: the corresponding nodes
# in each of the four trees, grouped by tree.
const NodeCorrespondence = @NamedTuple{
  original::Vector{YAMLNode},
  combined::Vector{YAMLNode},
  expanded::Vector{YAMLNode},
  leftover::Vector{YAMLNode}}

"""
    node_correspondence(lat::Lattices) -> Dict{YAMLNode, NodeCorrespondence}

Map every node of a [`Lattices`](@ref) to the nodes it corresponds to across the
`original`, `combined`, `expanded` and `leftover` trees.

The correspondence is exact: it is computed from provenance recorded while the
trees were derived from one another (`original` → `combined` → `expanded` and
`leftover`), not by re-matching after the fact. Because expansion can duplicate a
node (scalar substitution, `repeat`, `inherit`, forks), the correspondence is
one-to-many — a single `combined`/`original` node can map to several `expanded`
copies — so each field of the returned value is a `Vector{YAMLNode}`.

Expansion splits the document, so a node of `combined` may land in `expanded`, in
`leftover`, or in both: a definition that was substituted into the lattice is
copied there while its definition stays behind. Those copies share one
equivalence class, tied together through the `combined` node they came from.

# Returns
A `Dict` keyed by `YAMLNode`. For any node that participates in the
correspondence, `map[node]` is a named tuple
`(; original, combined, expanded, leftover)` of `Vector{YAMLNode}`, listing every
corresponding node grouped by tree. The queried node appears in its own tree's
vector, so the four vectors together are the full equivalence class of `node`. A
vector is empty when a tree has no corresponding node (e.g. the synthesised
`destination_pointer` scalar exists only in `expanded`, and a constant that the
lattice never references exists only in `leftover`).

# Example
```julia
lat = parse_and_expand_pals("lattice.pals.yaml")
corr = node_correspondence(lat)

a_const = lat.combined["PALS"]["facility"][1]["constants"]["a_const"]
corr[a_const].original   # the same constant in the original tree
corr[a_const].leftover   # constants are not part of the lattice, so they land here
corr[a_const].expanded   # empty unless the lattice referenced it
```
"""
function node_correspondence(lat::Lattices)
  ot = lat.original.tree
  ct = lat.combined.tree
  et = lat.expanded.tree
  lt = lat.leftover.tree

  cmap = @ccall (libyaml()).build_correspondence_map(
    ot.handle::Ptr{Cvoid}, ct.handle::Ptr{Cvoid}, et.handle::Ptr{Cvoid},
    lt.handle::Ptr{Cvoid})::CorrespondenceMapC

  links = try
    n = Int(cmap.count)
    n == 0 ? NodeLinkC[] : copy(unsafe_wrap(Array, cmap.links, n))
  finally
    @ccall (libyaml()).free_correspondence_map(cmap::CorrespondenceMapC)::Cvoid
  end

  # Each participating node is a (tree tag, id) key. A link ties together the
  # original/combined nodes of one logical entity with its copy in one of the two
  # derived trees; union those keys and then read off the connected components.
  # Copies that share a combined node — the same definition in `expanded` and in
  # `leftover` — are joined transitively through it.
  Key = Tuple{Symbol,Csize_t}
  parent = Dict{Key,Key}()

  add!(x) = (haskey(parent, x) || (parent[x] = x); x)
  function find!(x)
    root = x
    while parent[root] != root
      root = parent[root]
    end
    while parent[x] != root      # path compression
      parent[x], x = root, parent[x]
    end
    return root
  end
  uni!(a, b) = (parent[find!(a)] = find!(b))

  for l in links
    # A link names a node in exactly one of the two derived trees.
    kd = l.expanded != YAML_NULL_ID ? add!((:expanded, l.expanded)) :
                                      add!((:leftover, l.leftover))
    if l.combined != YAML_NULL_ID
      kc = add!((:combined, l.combined))
      uni!(kd, kc)
      if l.original != YAML_NULL_ID
        uni!(kc, add!((:original, l.original)))
      end
    end
  end

  # Gather the members of each connected component.
  groups = Dict{Key,Vector{Key}}()
  for k in keys(parent)
    push!(get!(groups, find!(k), Key[]), k)
  end

  treeof(tag) = tag === :original ? lat.original.tree :
                tag === :combined ? lat.combined.tree :
                tag === :expanded ? lat.expanded.tree : lat.leftover.tree
  nodeof(k) = YAMLNode(treeof(k[1]), k[2])

  result = Dict{YAMLNode,NodeCorrespondence}()
  for members in values(groups)
    entry = (
      original = YAMLNode[nodeof(k) for k in members if k[1] === :original],
      combined = YAMLNode[nodeof(k) for k in members if k[1] === :combined],
      expanded = YAMLNode[nodeof(k) for k in members if k[1] === :expanded],
      leftover = YAMLNode[nodeof(k) for k in members if k[1] === :leftover],
    )
    for k in members
      result[nodeof(k)] = entry
    end
  end
  return result
end

# ─── name matching ────────────────────────────────────────────────────────────

"""
    match_names(node, match_string) -> Vector{YAMLNode}

Return every named construct in `node`'s tree that is matched by `match_string`,
following PALS *Name Matching*. `node` may be any node of the tree to search
(typically a lattice-view root such as `lat.expanded`); the whole tree is
searched and the returned nodes belong to that same tree.

`match_string` has the form

    [{lattice}>>>][{branch}>>][{kind}::]{name}[>{group}.{sub}. … .{parameter}]

`{lattice}`, `{branch}`, and `{name}` are [PCRE2](https://www.pcre.org) patterns
matched against the whole name (anchored at both ends); `{kind}` is matched
exactly; the parameter path after the single `>` is matched exactly, key by key.
An omitted or empty pattern matches any name at that level. `{branch}` matches an
element if any enclosing BeamLine/Branch name matches, so elements in sub-lines
are included.

The node returned for each match is whatever the string resolves to: the element
node (no parameter path), the parameter-group or parameter node (with a path),
or — for a bare name (no lattice/branch/kind qualifier and no parameter path) —
additionally each matching constant and variable defined directly under the
`PALS` or `facility` node (both the full `kind: constant`/`kind: variable` and
the compact `constants:`/`variables:` forms). Lattice parameters therefore
include constant and variable names.

Which tree to search follows from that: elements are in `lat.expanded`, while
constants and variables are defined at facility level and so are found in
`lat.leftover`. Searching `lat.expanded` for a constant matches nothing, since
the `PALS`/`facility` node it would be defined under is not part of that tree.

Not yet implemented from *Element Name Matching*: `#N` instance selection,
`{e1}:{e2}` ranges, `,` unions, and `&` intersections.

Results are de-duplicated and returned in document order. A malformed pattern
yields an empty vector.

# Example
```julia
lat = parse_and_expand_pals("lattice.pals.yaml")

match_names(lat.expanded, "B1.*>BendP.e1")       # e1 of every B1… bend
match_names(lat.expanded, "Quadrupole::.*")      # every quadrupole element
match_names(lat.expanded, "inj>>>arc>>Q.*>length")  # length of arc's Q… in lattice inj
match_names(lat.leftover, "a_.*")                # constants/variables named a_…
```
"""
function match_names(node::YAMLNode, match_string::AbstractString)
  tree = node.tree
  m = @ccall (libyaml()).match_names(
    tree.handle::Ptr{Cvoid}, String(match_string)::Cstring)::NameMatchesC

  ids = try
    n = Int(m.count)
    n == 0 ? Csize_t[] : copy(unsafe_wrap(Array, m.nodes, n))
  finally
    @ccall (libyaml()).free_name_matches(m::NameMatchesC)::Cvoid
  end

  return YAMLNode[YAMLNode(tree, id) for id in ids]
end

# ─── parameter values ─────────────────────────────────────────────────────────

"""
    parameter_value(lat::Lattices, match_string) -> Float64 | String | Missing

Return the value of the lattice parameter named by `match_string`, looked up in
the expanded lattice `lat`.

`match_string` uses the same PALS *Name Matching* syntax as [`match_names`](@ref).
It names either an element parameter (with a `>{group}.{sub}. … .{parameter}`
path) or, as a *bare* name (no lattice/branch/kind qualifier and no path), a
constant or variable — the same constructs `match_names` resolves.

Only two of `lat`'s four views are searched: `lat.expanded`, which holds the
element parameters, and then, if the name is not found there, `lat.leftover`,
which holds the facility-level constants, variables, and any definitions not
spliced into the lattice. The raw `lat.original` and `lat.combined` views are
**not** searched — they carry unevaluated, pre-expansion text.

Because both searched views are post-expansion, values come back already
evaluated: a numeric value as a `Float64`, and a non-numeric one (e.g. a species
name like `"#3He"`, or an expression expansion left unevaluated such as one using
`random()`) verbatim as a `String`.

The value is resolved as follows:

  - **Element parameter, set:** its value — a `Float64`, or a `String` when
    non-numeric.
  - **Element parameter, not set:** the parameter's default is returned (`0.0`
    for every parameter, for now — real per-parameter defaults come later).
  - **Constant or variable (bare name):** its value, the same way.
  - **Nothing identified:** `missing`, when the name matches nothing in either
    view, names a bare element (an element has no single scalar value), stops on
    a whole parameter group, or several matches carry conflicting values.

# Example
```julia
lat = parse_and_expand_pals("lattice.pals.yaml")

parameter_value(lat, "quad1>MagneticMultipoleP.Bn1")  # 1.0        (from expanded)
parameter_value(lat, "quad1>BendP.g")                 # 0.0        (unset → default)
parameter_value(lat, "a_const")                       # a constant (from leftover)
parameter_value(lat, "quad1>nope.nope")               # missing
```
"""
function parameter_value(lat::Lattices, match_string::AbstractString)
  pv = @ccall (libyaml()).get_lattice_parameter_value(
    lat.expanded.tree.handle::Ptr{Cvoid}, lat.leftover.tree.handle::Ptr{Cvoid},
    String(match_string)::Cstring)::ParamValueC
  return _param_value_result(pv)
end

# Turn the raw ParamValueC returned by the C API into a Julia value: a `Float64`
# for a number, a `String` for a string (copied out, then the owning C string is
# freed), or `missing`.
function _param_value_result(pv::ParamValueC)
  pv.kind == PARAM_VALUE_NUMBER && return pv.number
  pv.kind == PARAM_VALUE_STRING || return missing
  s = unsafe_string(pv.string)
  @ccall (libyaml()).yaml_free_string(pv.string::Cstring)::Cvoid
  return s
end

# ─── parsing & memory ────────────────────────────────────────────────────────

"""
    parse_file(filename) -> YAMLNode

Parse a YAML file from disk. Returns a node pointing to the tree root.
"""
function parse_file(filename::String)
  isfile(filename) || error("File not found: $filename")
  handle = @ccall (libyaml()).parse_file(filename::Cstring)::Ptr{Cvoid}
  if handle == C_NULL
    msg = _last_parse_error()
    error("Failed to parse YAML file: $filename" * (isempty(msg) ? "" : "\n  $msg"))
  end
  return _root_node(handle)
end

#---------------------------------------------------------------------------------------------------

"""
    parse_string(yaml_str) -> YAMLNode

Parse a YAML string. Returns a node pointing to the tree root.
"""
function parse_string(yaml_str::String)
  handle = @ccall (libyaml()).parse_string(yaml_str::Cstring)::Ptr{Cvoid}
  if handle == C_NULL
    msg = _last_parse_error()
    error("Failed to parse YAML string" * (isempty(msg) ? "" : "\n  $msg"))
  end
  return _root_node(handle)
end

#---------------------------------------------------------------------------------------------------

"""
    create_empty_tree() -> YAMLNode

Create an empty MAP tree. Returns a node pointing to the root MAP.
"""
function create_empty_tree()
  handle = @ccall (libyaml()).create_empty_tree()::Ptr{Cvoid}
  return _root_node(handle)
end

# ─── type checks ─────────────────────────────────────────────────────────────

"""
    is_map(node) -> Bool

Return `true` if `node` is a MAP (a collection of key/value pairs), `false`
otherwise.  A node is exactly one of MAP, sequence, or scalar; use this to
decide before accessing children by key.
"""
is_map(node::YAMLNode) =
  @ccall (libyaml()).is_map(node.tree.handle::Ptr{Cvoid}, node.id::Csize_t)::Bool

#---------------------------------------------------------------------------------------------------

"""
    is_sequence(node) -> Bool

Return `true` if `node` is a sequence (an ordered list of elements), `false`
otherwise.  A node is exactly one of MAP, sequence, or scalar; use this to
decide before accessing children by index.
"""
is_sequence(node::YAMLNode) =
  @ccall (libyaml()).is_sequence(node.tree.handle::Ptr{Cvoid}, node.id::Csize_t)::Bool

#---------------------------------------------------------------------------------------------------

"""
    is_scalar(node) -> Bool

Return `true` if `node` is a scalar (a leaf holding a single string, number, or
boolean value), `false` otherwise.  A node is exactly one of MAP, sequence, or
scalar; scalar nodes have no children and their value is read with `String`,
`Int`, `Float64`, or `Bool`.
"""
is_scalar(node::YAMLNode) =
  @ccall (libyaml()).is_scalar(node.tree.handle::Ptr{Cvoid}, node.id::Csize_t)::Bool

# ─── traversal ───────────────────────────────────────────────────────────────

"""
    get_parent(node) -> YAMLNode

Return the parent of `node`, or error if `node` is the root (which has no
parent).
"""
function get_parent(node::YAMLNode)
  id = @ccall (libyaml()).get_parent(node.tree.handle::Ptr{Cvoid}, node.id::Csize_t)::Csize_t
  id == YAML_NULL_ID && error("Node has no parent (it is the root)")
  return YAMLNode(node.tree, id)
end

#---------------------------------------------------------------------------------------------------

"""
    node[key] -> YAMLNode

Look up a direct child of a MAP `node` by its string `key` and return that
child node.  Only direct children are searched (the lookup is not recursive).
Throws an error if no child has the given key; call `haskey(node, key)` first
if the key may be absent.
"""
function Base.getindex(node::YAMLNode, key::String)
  id = @ccall (libyaml()).get_child_by_key(
    node.tree.handle::Ptr{Cvoid}, node.id::Csize_t, key::Cstring)::Csize_t
  id == YAML_NULL_ID && error("Key not found: $key")
  return YAMLNode(node.tree, id)
end

#---------------------------------------------------------------------------------------------------

"""
    node[index] -> YAMLNode

Return the `index`-th direct child of a MAP or sequence `node`.  Indexing is
1-based, matching Julia convention (the underlying C API is 0-based).  Throws
an error if `index` is out of bounds.
"""
function Base.getindex(node::YAMLNode, index::Int)
  id = @ccall (libyaml()).get_child_by_index(
    node.tree.handle::Ptr{Cvoid}, node.id::Csize_t, Csize_t(index - 1)::Csize_t)::Csize_t
  id == YAML_NULL_ID && error("Index out of bounds: $index")
  return YAMLNode(node.tree, id)
end

#---------------------------------------------------------------------------------------------------

"""
    haskey(node, key) -> Bool

Return `true` if the MAP `node` has a direct child stored under the string
`key`, `false` otherwise.  Only direct children are checked; the search is not
recursive.  Useful as a guard before `node[key]`, which errors on a missing key.
"""
function Base.haskey(node::YAMLNode, key::String)
  id = @ccall (libyaml()).get_child_by_key(
    node.tree.handle::Ptr{Cvoid}, node.id::Csize_t, key::Cstring)::Csize_t
  return id != YAML_NULL_ID
end

#---------------------------------------------------------------------------------------------------

"""
    length(node) -> Int

Return the number of direct children of `node`: the number of key/value pairs
in a MAP, or the number of elements in a sequence.  Scalar nodes report 0.
Only direct children are counted (the count is not recursive).
"""
function Base.length(node::YAMLNode)
  Int(@ccall (libyaml()).get_size(node.tree.handle::Ptr{Cvoid}, node.id::Csize_t)::Csize_t)
end

#---------------------------------------------------------------------------------------------------

"""
    keys(node) -> Vector{String}

Return the keys of a MAP `node`, in document order, as a `Vector{String}`.
Returns an empty vector for sequence or scalar nodes.  Pair with `node[key]` to
retrieve each value, or iterate the node directly to get `(key, value)` pairs.
"""
function Base.keys(node::YAMLNode)
  is_map(node) || return String[]
  n = length(node)
  result = Vector{String}(undef, n)
  for i in 0:(n - 1)
    child_id = @ccall (libyaml()).get_child_by_index(
      node.tree.handle::Ptr{Cvoid}, node.id::Csize_t, Csize_t(i)::Csize_t)::Csize_t
    child_id == YAML_NULL_ID && continue
    key_ptr = @ccall (libyaml()).get_node_key(
      node.tree.handle::Ptr{Cvoid}, child_id::Csize_t)::Cstring
    key_ptr == C_NULL && continue
    result[i + 1] = unsafe_string(key_ptr)
    @ccall (libyaml()).yaml_free_string(key_ptr::Cstring)::Cvoid
  end
  return result
end

#---------------------------------------------------------------------------------------------------

"""
    node_key(node) -> Union{String,Nothing}

Return the key under which `node` is stored in its parent MAP, as a `String`,
or `nothing` if `node` has no key.  Sequence elements and the tree root have no
key and return `nothing`.
"""
function node_key(node::YAMLNode)
  ptr = @ccall (libyaml()).get_node_key(
    node.tree.handle::Ptr{Cvoid}, node.id::Csize_t)::Cstring
  ptr == C_NULL && return nothing
  s = unsafe_string(ptr)
  @ccall (libyaml()).yaml_free_string(ptr::Cstring)::Cvoid
  return s
end

#---------------------------------------------------------------------------------------------------

"""
    iterate(node[, state])

Iterate over the children of `node`, enabling `for` loops, comprehensions, and
`collect`.  Sequences yield successive `YAMLNode` elements; maps yield
`(key, YAMLNode)` pairs (with `key::String`).  Scalar nodes yield nothing.
"""
function Base.iterate(node::YAMLNode, state=1)
  if is_sequence(node)
    state > length(node) && return nothing
    return (node[state], state + 1)
  elseif is_map(node)
    ks = keys(node)
    state > length(ks) && return nothing
    k = ks[state]
    return ((k, node[k]), state + 1)
  else
    return nothing
  end
end

#---------------------------------------------------------------------------------------------------

Base.eachindex(node::YAMLNode) = (is_sequence(node) || is_map(node)) ? (1:length(node)) : (1:0)

# ─── reading values ───────────────────────────────────────────────────────────

"""
    String(node) -> String

Return the scalar value of `node` as a `String`.  Throws an error if `node` is
not a scalar (i.e. it is a MAP or sequence); guard with `is_scalar(node)` if
unsure.  This is the raw text; use `Int`, `Float64`, or `Bool` for typed values.
"""
function Base.String(node::YAMLNode)
  ptr = @ccall (libyaml()).as_string(
    node.tree.handle::Ptr{Cvoid}, node.id::Csize_t)::Cstring
  ptr == C_NULL && error("Node has no scalar value")
  s = unsafe_string(ptr)
  @ccall (libyaml()).yaml_free_string(ptr::Cstring)::Cvoid
  return s
end

#---------------------------------------------------------------------------------------------------

"""
    Int(node) -> Int

Parse the scalar value of `node` as an `Int`.  Throws if `node` is not a scalar
or if its text is not a valid integer.
"""
Base.Int(node::YAMLNode)     = parse(Int,     String(node))

#---------------------------------------------------------------------------------------------------

"""
    Float64(node) -> Float64

Parse the scalar value of `node` as a `Float64`.  Throws if `node` is not a
scalar or if its text is not a valid floating-point number.
"""
Base.Float64(node::YAMLNode) = parse(Float64, String(node))

#---------------------------------------------------------------------------------------------------

"""
    Bool(node) -> Bool

Parse the scalar value of `node` as a `Bool`.  Accepts exactly the text
`"true"` or `"false"`; any other value (or a non-scalar node) throws an error.
"""
function Base.Bool(node::YAMLNode)
  s = String(node)
  s == "true"  && return true
  s == "false" && return false
  error("Cannot convert '$s' to Bool")
end

# ─── modification ────────────────────────────────────────────────────────────

# Nullable key helper: branches on nothing to avoid passing a Julia String
# through a Cstring slot when the C side expects NULL.
macro _ccall_add(fn, tree, parent_id, key, rest...)
  quote
    if $(esc(key)) === nothing
      @ccall (libyaml()).$(fn)($(esc(tree))::Ptr{Cvoid}, $(esc(parent_id))::Csize_t,
        C_NULL::Ptr{Cchar}, $(map(esc, rest)...))::Csize_t
    else
      @ccall (libyaml()).$(fn)($(esc(tree))::Ptr{Cvoid}, $(esc(parent_id))::Csize_t,
        $(esc(key))::Cstring, $(map(esc, rest)...))::Csize_t
    end
  end
end

#---------------------------------------------------------------------------------------------------

"""
    add_scalar!(parent, value; key=nothing, index=nothing) -> YAMLNode

Add a scalar child to `parent`.  Pass `key` for MAP parents; omit it (or pass
`nothing`) for sequence elements.  `index` selects the 1-based position among
`parent`'s existing children; the default `index=nothing` appends at the end.
"""
function add_scalar!(parent::YAMLNode, value::String;
                     key::Union{String,Nothing}=nothing,
                     index::Union{Integer,Nothing}=nothing)
  c_index = index === nothing ? YAML_NULL_ID : Csize_t(index - 1)
  id = if key === nothing
    @ccall (libyaml()).add_scalar(
      parent.tree.handle::Ptr{Cvoid}, parent.id::Csize_t,
      C_NULL::Ptr{Cchar}, value::Cstring, c_index::Csize_t)::Csize_t
  else
    @ccall (libyaml()).add_scalar(
      parent.tree.handle::Ptr{Cvoid}, parent.id::Csize_t,
      key::Cstring, value::Cstring, c_index::Csize_t)::Csize_t
  end
  id == YAML_NULL_ID && error("Failed to add scalar")
  return YAMLNode(parent.tree, id)
end

#---------------------------------------------------------------------------------------------------

"""
    add_map!(parent; key=nothing, index=nothing) -> YAMLNode

Add an empty MAP child to `parent`.  Pass `key` for MAP parents; omit it (or
pass `nothing`) for sequence elements.  `index` selects the 1-based position
among `parent`'s existing children; the default `index=nothing` appends at the
end.
"""
function add_map!(parent::YAMLNode;
                  key::Union{String,Nothing}=nothing,
                  index::Union{Integer,Nothing}=nothing)
  c_index = index === nothing ? YAML_NULL_ID : Csize_t(index - 1)
  id = if key === nothing
    @ccall (libyaml()).add_map(
      parent.tree.handle::Ptr{Cvoid}, parent.id::Csize_t,
      C_NULL::Ptr{Cchar}, c_index::Csize_t)::Csize_t
  else
    @ccall (libyaml()).add_map(
      parent.tree.handle::Ptr{Cvoid}, parent.id::Csize_t,
      key::Cstring, c_index::Csize_t)::Csize_t
  end
  id == YAML_NULL_ID && error("Failed to add map")
  return YAMLNode(parent.tree, id)
end

#---------------------------------------------------------------------------------------------------

"""
    add_sequence!(parent; key=nothing, index=nothing) -> YAMLNode

Add an empty sequence child to `parent`.  Pass `key` for MAP parents; omit it
(or pass `nothing`) for sequence elements.  `index` selects the 1-based position
among `parent`'s existing children; the default `index=nothing` appends at the
end.
"""
function add_sequence!(parent::YAMLNode;
                       key::Union{String,Nothing}=nothing,
                       index::Union{Integer,Nothing}=nothing)
  c_index = index === nothing ? YAML_NULL_ID : Csize_t(index - 1)
  id = if key === nothing
    @ccall (libyaml()).add_sequence(
      parent.tree.handle::Ptr{Cvoid}, parent.id::Csize_t,
      C_NULL::Ptr{Cchar}, c_index::Csize_t)::Csize_t
  else
    @ccall (libyaml()).add_sequence(
      parent.tree.handle::Ptr{Cvoid}, parent.id::Csize_t,
      key::Cstring, c_index::Csize_t)::Csize_t
  end
  id == YAML_NULL_ID && error("Failed to add sequence")
  return YAMLNode(parent.tree, id)
end

#---------------------------------------------------------------------------------------------------

"""
    node[key] = value

Set or update a scalar value in a MAP node.  If `key` already exists its
value is updated with `set_scalar`; otherwise a new scalar child is appended.
"""
function Base.setindex!(node::YAMLNode, value::String, key::String)
  child_id = @ccall (libyaml()).get_child_by_key(
    node.tree.handle::Ptr{Cvoid}, node.id::Csize_t, key::Cstring)::Csize_t
  if child_id != YAML_NULL_ID
    @ccall (libyaml()).set_scalar(
      node.tree.handle::Ptr{Cvoid}, child_id::Csize_t, value::Cstring)::Cvoid
  else
    @ccall (libyaml()).add_scalar(
      node.tree.handle::Ptr{Cvoid}, node.id::Csize_t,
      key::Cstring, value::Cstring, YAML_NULL_ID::Csize_t)::Csize_t
  end
end

#---------------------------------------------------------------------------------------------------

"""
    set_scalar!(node, value)

Set or replace the scalar value of `node` with the string `value`.  Operates on
an existing node in place; to set a value by key within a MAP (adding the key if
absent), use `node[key] = value` instead.
"""
function set_scalar!(node::YAMLNode, value::String)
  @ccall (libyaml()).set_scalar(
    node.tree.handle::Ptr{Cvoid}, node.id::Csize_t, value::Cstring)::Cvoid
end

#---------------------------------------------------------------------------------------------------

"""
    set_key!(node, key)

Set or replace the key under which `node` is stored in its parent MAP to the
string `key`.  Only meaningful for nodes that live inside a MAP; sequence
elements are keyless.
"""
function set_key!(node::YAMLNode, key::String)
  @ccall (libyaml()).set_node_key(
    node.tree.handle::Ptr{Cvoid}, node.id::Csize_t, key::Cstring)::Cvoid
end

#---------------------------------------------------------------------------------------------------

"""
    remove!(node)

Remove `node`, together with all of its descendants, from its parent.  After
removal the `YAMLNode` handle is stale and must not be used again.  Intended for
non-root nodes; the root has no parent to be removed from.
"""
function remove!(node::YAMLNode)
  parent_id = @ccall (libyaml()).get_parent(
    node.tree.handle::Ptr{Cvoid}, node.id::Csize_t)::Csize_t
  @ccall (libyaml()).remove_node(
    node.tree.handle::Ptr{Cvoid}, parent_id::Csize_t, node.id::Csize_t)::Cvoid
end

# ─── deep copy ───────────────────────────────────────────────────────────────

"""
    deep_copy_node!(dst, src)

Copy the type, key, value, and all descendants of `src` into `dst`,
overwriting whatever `dst` previously held.  Works across different trees.
"""
function deep_copy_node!(dst::YAMLNode, src::YAMLNode)
  @ccall (libyaml()).deep_copy_node(
    dst.tree.handle::Ptr{Cvoid}, dst.id::Csize_t,
    src.tree.handle::Ptr{Cvoid}, src.id::Csize_t)::Cvoid
end

#---------------------------------------------------------------------------------------------------

"""
    deep_copy_children!(dst, src; index=nothing)

Copy all children of `src` into `dst` at the 1-based position `index` among
`dst`'s existing children; the default `index=nothing` appends them at the end.
Works across different trees.
"""
function deep_copy_children!(dst::YAMLNode, src::YAMLNode; index::Union{Integer,Nothing}=nothing)
  c_index = index === nothing ? YAML_NULL_ID : Csize_t(index - 1)
  @ccall (libyaml()).deep_copy_children(
    dst.tree.handle::Ptr{Cvoid}, dst.id::Csize_t,
    src.tree.handle::Ptr{Cvoid}, src.id::Csize_t,
    c_index::Csize_t)::Cvoid
end

#---------------------------------------------------------------------------------------------------

"""
    Base.copy(node) -> YAMLNode

Return an independent deep copy of `node` in a new tree.
"""
function Base.copy(node::YAMLNode)
  dst = create_empty_tree()
  deep_copy_node!(dst, node)
  return dst
end

# ─── emitting ────────────────────────────────────────────────────────────────

# What the `exclude` keyword of to_yaml_string / write_yaml accepts: one key
# name, or a collection of them.
const ExcludeKeys = Union{AbstractString,AbstractVector{<:AbstractString}}

_exclude_set(exclude::ExcludeKeys) =
  exclude isa AbstractString ? Set([String(exclude)]) : Set(String.(exclude))

#---------------------------------------------------------------------------------------------------

"""
    to_yaml_string(node; exclude=String[]) -> String

Emit `node` and its descendants as a YAML string.

`exclude` is a key name, or a collection of key names, to be left out of the
output: every MAP entry whose key matches, at any depth, is omitted along with
its whole subtree.  This is a display filter only -- `node` itself is never
modified.  For example, to print a lattice without the floor and reference
subtrees:

    println(to_yaml_string(lat, exclude = ["FloorP", "ReferenceP"]))
"""
function to_yaml_string(node::YAMLNode; exclude::ExcludeKeys=String[])
  drop = _exclude_set(exclude)
  isempty(drop) && return _emit_yaml(node)
  # `GC.@preserve` keeps the throw-away copy's tree alive across the emit, since
  # nothing else holds a reference to it.
  pruned = _pruned_copy(node, drop)
  GC.@preserve pruned begin
    return _emit_yaml(pruned)
  end
end

#---------------------------------------------------------------------------------------------------

# Emit `node` and its descendants as YAML, without any filtering.

function _emit_yaml(node::YAMLNode)
  ptr = @ccall (libyaml()).node_to_string(
    node.tree.handle::Ptr{Cvoid}, node.id::Csize_t)::Cstring
  ptr == C_NULL && error("Cannot convert node to YAML string")
  s = unsafe_string(ptr)
  @ccall (libyaml()).yaml_free_string(ptr::Cstring)::Cvoid
  return s
end

#---------------------------------------------------------------------------------------------------

# An independent copy of `node`, in a tree of its own, with every entry keyed by
# a name in `drop` removed. The caller's tree is left untouched.

function _pruned_copy(node::YAMLNode, drop::Set{String})
  pruned = copy(node)
  _prune_keys!(pruned, drop)
  return pruned
end

#---------------------------------------------------------------------------------------------------

# Recursively remove, in place, every MAP entry of `node` whose key is in `drop`.

function _prune_keys!(node::YAMLNode, drop::Set{String})
  if is_map(node)
    for k in keys(node)
      child = node[k]
      k in drop ? remove!(child) : _prune_keys!(child, drop)
    end
  elseif is_sequence(node)
    for i in 1:length(node)
      _prune_keys!(node[i], drop)
    end
  end
  return node
end

#---------------------------------------------------------------------------------------------------

"""
    write_yaml(node, filename; exclude=String[]) -> Bool

Write the entire tree that contains `node` to a YAML file.
Returns `true` on success.

`exclude` is a key name, or a collection of key names, to be left out of the
file: every MAP entry whose key matches, at any depth, is omitted along with its
whole subtree.  The tree in memory is not modified.  For example, to write a
lattice without the floor and reference subtrees:

    write_yaml(lat, "out.pals.yaml", exclude = ["FloorP", "ReferenceP"])
"""
function write_yaml(node::YAMLNode, filename::String; exclude::ExcludeKeys=String[])
  drop = _exclude_set(exclude)
  # Prune a throw-away copy of the whole tree, then write that copy instead.
  # `GC.@preserve` keeps that copy's tree alive across the call, since nothing
  # else holds a reference to it.
  target = isempty(drop) ? node : _pruned_copy(_tree_root(node), drop)
  GC.@preserve target begin
    return Bool(@ccall (libyaml()).write_file(
      target.tree.handle::Ptr{Cvoid}, filename::Cstring)::Bool)
  end
end

# ─── display ─────────────────────────────────────────────────────────────────

function Base.show(io::IO, node::YAMLNode)
  if is_scalar(node)
    print(io, "YAMLNode(scalar: ", String(node), ")")
  elseif is_map(node)
    print(io, "YAMLNode(map, ", length(node), " keys)")
  elseif is_sequence(node)
    print(io, "YAMLNode(sequence, ", length(node), " elements)")
  else
    print(io, "YAMLNode(unknown)")
  end
end

# Multi-line display used by the REPL (and anywhere that requests the
# `text/plain` MIME). Prints the node's contents as YAML so a `YAMLNode`
# shows its full tree automatically, while the compact `show` above is
# still used for nested contexts such as arrays and dicts.
function Base.show(io::IO, ::MIME"text/plain", node::YAMLNode)
  print(io, rstrip(to_yaml_string(node)))
end
