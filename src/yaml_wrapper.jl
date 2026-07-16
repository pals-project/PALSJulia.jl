# ─── internal helpers ────────────────────────────────────────────────────────

# Wrap a tree handle and return a node pointing to its root.
function _root_node(handle::Ptr{Cvoid})
  tree    = YAMLTree(handle)
  root_id = @ccall LIBYAML.get_root(handle::Ptr{Cvoid})::Csize_t
  return YAMLNode(tree, root_id)
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
  @ccall LIBYAML.free_lattice_problems(sl::StringListC)::Cvoid
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

Parse a PALS lattice file and return its `original`, `combined`, and `expanded`
views as a [`Lattices`](@ref).

# Arguments
- `filename`: Path to the top-level YAML lattice file.
- `root_lattice`: Name of the lattice to expand. If empty (the default), the
  lattice to expand is chosen with the following priority:
    1. the lattice named by the last `use` statement, or
    2. the last lattice defined in the file if no `use` statement is present.
- `problems`: What to do with the list of problems found while building the
  `expanded` tree (undefined lattice, dangling element/line references,
  undefined `inherit`/`repeat`/`Fork` targets, and expressions that could not
  be evaluated). One of:
    - `:print` (the default) — print the problems to `stderr` (nothing is
      printed when there are none);
    - a filename `String` — write the problems to that file, printing nothing;
    - `:none` — do nothing (no printing, no file).

# Returns
A `Lattices` with three independent tree views:
- `Lattices[1]`: The `original` lattice. The tree as read in, mapping each file (including
  any `include`d files) to its unparsed contents.
- `Lattices[2]`: The `combined` lattice: the tree with all `include` directives resolved and spliced inline.
- `Lattices[3]`: The `expanded` lattice: the tree with the selected lattice fully expanded — scalars
  substituted with their full definitions, `repeat`ed beamlines unrolled,
  `inherit`ed ancestors merged in, forks resolved, and every mathematical
  expression evaluated to a number (see [`evaluate_pals_expression`](@ref);
  `random()`/`random_gauss()` are left as text). `Controller` elements are
  evaluated against their own scoped variable tables, with each control
  `expression` computed and stored back in its control entry.

Each view is backed by its own `YAMLNode`; all three are freed independently
when their nodes are garbage collected.
"""
function parse_and_expand_pals(filename::String, root_lattice::String="";
                               problems::Union{Symbol,AbstractString}=:print)
  isfile(filename) || error("File not found: $filename")
  (problems isa AbstractString || problems === :print || problems === :none) ||
    throw(ArgumentError("`problems` must be :print, :none, or a filename string"))

  handles = @ccall LIBYAML.parse_and_expand_PALS(
    filename::Cstring,
    root_lattice::Cstring
  )::LatticesHandle

  # Take ownership of the problem list before anything can error out.
  problem_list = _take_problem_list(handles.problems)

  (handles.original == C_NULL || handles.combined == C_NULL || handles.expanded == C_NULL) &&
    error("Failed to parse lattice file: $filename")

  _report_problems(problem_list, problems)

  return Lattices(
    _root_node(handles.original),
    _root_node(handles.combined),
    _root_node(handles.expanded),
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
  val = @ccall LIBYAML.evaluate_pals_expression(
    String(expr)::Cstring, ok::Ref{Bool})::Cdouble
  ok[] || throw(ArgumentError("Not an evaluable PALS expression: \"$expr\""))
  return val
end

# ─── node correspondence ──────────────────────────────────────────────────────

# Concrete value type stored in the correspondence Dict: the corresponding nodes
# in each of the three trees, grouped by tree.
const NodeCorrespondence = @NamedTuple{
  original::Vector{YAMLNode},
  combined::Vector{YAMLNode},
  expanded::Vector{YAMLNode}}

"""
    node_correspondence(lat::Lattices) -> Dict{YAMLNode, NodeCorrespondence}

Map every node of a [`Lattices`](@ref) to the nodes it corresponds to across the
`original`, `combined`, and `expanded` trees.

The correspondence is exact: it is computed from provenance recorded while the
three trees were derived from one another (`original` → `combined` → `expanded`),
not by re-matching after the fact. Because expansion can duplicate a node
(scalar substitution, `repeat`, `inherit`, forks), the correspondence is
one-to-many — a single `combined`/`original` node can map to several `expanded`
copies — so each field of the returned value is a `Vector{YAMLNode}`.

# Returns
A `Dict` keyed by `YAMLNode`. For any node that participates in the
correspondence, `map[node]` is a named tuple `(; original, combined, expanded)`
of `Vector{YAMLNode}`, listing every corresponding node grouped by tree. The
queried node appears in its own tree's vector, so the three vectors together are
the full equivalence class of `node`. A vector is empty when a tree has no
corresponding node (e.g. the synthesised `fork_pointer` scalar exists only in
`expanded`).

# Example
```julia
lat = parse_and_expand_pals("lattice.pals.yaml")
corr = node_correspondence(lat)

a_const = lat.combined["PALS"]["facility"][1]["constants"]["a_const"]
corr[a_const].original   # the same constant in the original tree
corr[a_const].expanded   # its copies in the expanded tree
```
"""
function node_correspondence(lat::Lattices)
  ot = lat.original.tree
  ct = lat.combined.tree
  et = lat.expanded.tree

  cmap = @ccall LIBYAML.build_correspondence_map(
    ot.handle::Ptr{Cvoid}, ct.handle::Ptr{Cvoid}, et.handle::Ptr{Cvoid})::CorrespondenceMapC

  links = try
    n = Int(cmap.count)
    n == 0 ? NodeLinkC[] : copy(unsafe_wrap(Array, cmap.links, n))
  finally
    @ccall LIBYAML.free_correspondence_map(cmap::CorrespondenceMapC)::Cvoid
  end

  # Each participating node is a (tree tag, id) key. A link ties together the
  # original/combined/expanded nodes of one logical entity; union those keys and
  # then read off the connected components.
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
    ke = add!((:expanded, l.expanded))
    if l.combined != YAML_NULL_ID
      kc = add!((:combined, l.combined))
      uni!(ke, kc)
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
                tag === :combined ? lat.combined.tree : lat.expanded.tree
  nodeof(k) = YAMLNode(treeof(k[1]), k[2])

  result = Dict{YAMLNode,NodeCorrespondence}()
  for members in values(groups)
    entry = (
      original = YAMLNode[nodeof(k) for k in members if k[1] === :original],
      combined = YAMLNode[nodeof(k) for k in members if k[1] === :combined],
      expanded = YAMLNode[nodeof(k) for k in members if k[1] === :expanded],
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
match_names(lat.expanded, "a_.*")                # constants/variables named a_…
```
"""
function match_names(node::YAMLNode, match_string::AbstractString)
  tree = node.tree
  m = @ccall LIBYAML.match_names(
    tree.handle::Ptr{Cvoid}, String(match_string)::Cstring)::NameMatchesC

  ids = try
    n = Int(m.count)
    n == 0 ? Csize_t[] : copy(unsafe_wrap(Array, m.nodes, n))
  finally
    @ccall LIBYAML.free_name_matches(m::NameMatchesC)::Cvoid
  end

  return YAMLNode[YAMLNode(tree, id) for id in ids]
end

# ─── parsing & memory ────────────────────────────────────────────────────────

"""
    parse_file(filename) -> YAMLNode

Parse a YAML file from disk. Returns a node pointing to the tree root.
"""
function parse_file(filename::String)
  isfile(filename) || error("File not found: $filename")
  handle = @ccall LIBYAML.parse_file(filename::Cstring)::Ptr{Cvoid}
  handle == C_NULL && error("Failed to parse YAML file: $filename")
  return _root_node(handle)
end

#---------------------------------------------------------------------------------------------------

"""
    parse_string(yaml_str) -> YAMLNode

Parse a YAML string. Returns a node pointing to the tree root.
"""
function parse_string(yaml_str::String)
  handle = @ccall LIBYAML.parse_string(yaml_str::Cstring)::Ptr{Cvoid}
  handle == C_NULL && error("Failed to parse YAML string")
  return _root_node(handle)
end

#---------------------------------------------------------------------------------------------------

"""
    create_empty_tree() -> YAMLNode

Create an empty MAP tree. Returns a node pointing to the root MAP.
"""
function create_empty_tree()
  handle = @ccall LIBYAML.create_empty_tree()::Ptr{Cvoid}
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
  @ccall LIBYAML.is_map(node.tree.handle::Ptr{Cvoid}, node.id::Csize_t)::Bool

#---------------------------------------------------------------------------------------------------

"""
    is_sequence(node) -> Bool

Return `true` if `node` is a sequence (an ordered list of elements), `false`
otherwise.  A node is exactly one of MAP, sequence, or scalar; use this to
decide before accessing children by index.
"""
is_sequence(node::YAMLNode) =
  @ccall LIBYAML.is_sequence(node.tree.handle::Ptr{Cvoid}, node.id::Csize_t)::Bool

#---------------------------------------------------------------------------------------------------

"""
    is_scalar(node) -> Bool

Return `true` if `node` is a scalar (a leaf holding a single string, number, or
boolean value), `false` otherwise.  A node is exactly one of MAP, sequence, or
scalar; scalar nodes have no children and their value is read with `String`,
`Int`, `Float64`, or `Bool`.
"""
is_scalar(node::YAMLNode) =
  @ccall LIBYAML.is_scalar(node.tree.handle::Ptr{Cvoid}, node.id::Csize_t)::Bool

# ─── traversal ───────────────────────────────────────────────────────────────

"""
    get_parent(node) -> YAMLNode

Return the parent of `node`, or error if `node` is the root (which has no
parent).
"""
function get_parent(node::YAMLNode)
  id = @ccall LIBYAML.get_parent(node.tree.handle::Ptr{Cvoid}, node.id::Csize_t)::Csize_t
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
  id = @ccall LIBYAML.get_child_by_key(
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
  id = @ccall LIBYAML.get_child_by_index(
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
  id = @ccall LIBYAML.get_child_by_key(
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
  Int(@ccall LIBYAML.get_size(node.tree.handle::Ptr{Cvoid}, node.id::Csize_t)::Csize_t)
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
    child_id = @ccall LIBYAML.get_child_by_index(
      node.tree.handle::Ptr{Cvoid}, node.id::Csize_t, Csize_t(i)::Csize_t)::Csize_t
    child_id == YAML_NULL_ID && continue
    key_ptr = @ccall LIBYAML.get_node_key(
      node.tree.handle::Ptr{Cvoid}, child_id::Csize_t)::Cstring
    key_ptr == C_NULL && continue
    result[i + 1] = unsafe_string(key_ptr)
    @ccall LIBYAML.yaml_free_string(key_ptr::Cstring)::Cvoid
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
  ptr = @ccall LIBYAML.get_node_key(
    node.tree.handle::Ptr{Cvoid}, node.id::Csize_t)::Cstring
  ptr == C_NULL && return nothing
  s = unsafe_string(ptr)
  @ccall LIBYAML.yaml_free_string(ptr::Cstring)::Cvoid
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
  ptr = @ccall LIBYAML.as_string(
    node.tree.handle::Ptr{Cvoid}, node.id::Csize_t)::Cstring
  ptr == C_NULL && error("Node has no scalar value")
  s = unsafe_string(ptr)
  @ccall LIBYAML.yaml_free_string(ptr::Cstring)::Cvoid
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
      @ccall LIBYAML.$(fn)($(esc(tree))::Ptr{Cvoid}, $(esc(parent_id))::Csize_t,
        C_NULL::Ptr{Cchar}, $(map(esc, rest)...))::Csize_t
    else
      @ccall LIBYAML.$(fn)($(esc(tree))::Ptr{Cvoid}, $(esc(parent_id))::Csize_t,
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
    @ccall LIBYAML.add_scalar(
      parent.tree.handle::Ptr{Cvoid}, parent.id::Csize_t,
      C_NULL::Ptr{Cchar}, value::Cstring, c_index::Csize_t)::Csize_t
  else
    @ccall LIBYAML.add_scalar(
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
    @ccall LIBYAML.add_map(
      parent.tree.handle::Ptr{Cvoid}, parent.id::Csize_t,
      C_NULL::Ptr{Cchar}, c_index::Csize_t)::Csize_t
  else
    @ccall LIBYAML.add_map(
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
    @ccall LIBYAML.add_sequence(
      parent.tree.handle::Ptr{Cvoid}, parent.id::Csize_t,
      C_NULL::Ptr{Cchar}, c_index::Csize_t)::Csize_t
  else
    @ccall LIBYAML.add_sequence(
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
  child_id = @ccall LIBYAML.get_child_by_key(
    node.tree.handle::Ptr{Cvoid}, node.id::Csize_t, key::Cstring)::Csize_t
  if child_id != YAML_NULL_ID
    @ccall LIBYAML.set_scalar(
      node.tree.handle::Ptr{Cvoid}, child_id::Csize_t, value::Cstring)::Cvoid
  else
    @ccall LIBYAML.add_scalar(
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
  @ccall LIBYAML.set_scalar(
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
  @ccall LIBYAML.set_node_key(
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
  parent_id = @ccall LIBYAML.get_parent(
    node.tree.handle::Ptr{Cvoid}, node.id::Csize_t)::Csize_t
  @ccall LIBYAML.remove_node(
    node.tree.handle::Ptr{Cvoid}, parent_id::Csize_t, node.id::Csize_t)::Cvoid
end

# ─── deep copy ───────────────────────────────────────────────────────────────

"""
    deep_copy_node!(dst, src)

Copy the type, key, value, and all descendants of `src` into `dst`,
overwriting whatever `dst` previously held.  Works across different trees.
"""
function deep_copy_node!(dst::YAMLNode, src::YAMLNode)
  @ccall LIBYAML.deep_copy_node(
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
  @ccall LIBYAML.deep_copy_children(
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

"""
    to_yaml_string(node) -> String

Emit `node` and its descendants as a YAML string.
"""
function to_yaml_string(node::YAMLNode)
  ptr = @ccall LIBYAML.node_to_string(
    node.tree.handle::Ptr{Cvoid}, node.id::Csize_t)::Cstring
  ptr == C_NULL && error("Cannot convert node to YAML string")
  s = unsafe_string(ptr)
  @ccall LIBYAML.yaml_free_string(ptr::Cstring)::Cvoid
  return s
end

#---------------------------------------------------------------------------------------------------

"""
    write_yaml(node, filename) -> Bool

Write the entire tree that contains `node` to a YAML file.
Returns `true` on success.
"""
function write_yaml(node::YAMLNode, filename::String)
  Bool(@ccall LIBYAML.write_file(node.tree.handle::Ptr{Cvoid}, filename::Cstring)::Bool)
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
