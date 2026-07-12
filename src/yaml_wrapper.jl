# ─── internal helpers ────────────────────────────────────────────────────────

# Wrap a tree handle and return a node pointing to its root.
function _root_node(handle::Ptr{Cvoid})
  tree    = YAMLTree(handle)
  root_id = @ccall LIBYAML.get_root(handle::Ptr{Cvoid})::Csize_t
  return YAMLNode(tree, root_id)
end

# ─── parse_and_expand_pals ────────────────────────────────────────────────────

"""
    parse_and_expand_pals(filename, lattice_name="") -> Lattices

Parse a lattice file and return original, included, and expanded views.
All three are freed independently when their `YAMLNode`s are GC'd.
"""
function parse_and_expand_pals(filename::String, lattice_name::String="")
  isfile(filename) || error("File not found: $filename")
  handles = @ccall LIBYAML.parse_and_expand_PALS(
    filename::Cstring,
    lattice_name::Cstring
  )::LatticesHandle

  (handles.original == C_NULL || handles.included == C_NULL || handles.expanded == C_NULL) &&
    error("Failed to parse lattice file: $filename")

  return Lattices(
    _root_node(handles.original),
    _root_node(handles.included),
    _root_node(handles.expanded),
  )
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
    add_scalar!(parent, value; key=nothing, index=END) -> YAMLNode

Add a scalar child to `parent`.  Pass `key` for MAP parents; omit (or pass
`nothing`) for sequence elements.  `index` is 1-based; use `END` to append.
"""
function add_scalar!(parent::YAMLNode, value::String;
                     key::Union{String,Nothing}=nothing,
                     index::Integer=END)
  c_index = index == END ? END : Csize_t(index - 1)
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
    add_map!(parent; key=nothing, index=END) -> YAMLNode

Add an empty MAP child to `parent`.
"""
function add_map!(parent::YAMLNode;
                  key::Union{String,Nothing}=nothing,
                  index::Integer=END)
  c_index = index == END ? END : Csize_t(index - 1)
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
    add_sequence!(parent; key=nothing, index=END) -> YAMLNode

Add an empty sequence child to `parent`.
"""
function add_sequence!(parent::YAMLNode;
                       key::Union{String,Nothing}=nothing,
                       index::Integer=END)
  c_index = index == END ? END : Csize_t(index - 1)
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
      key::Cstring, value::Cstring, END::Csize_t)::Csize_t
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
    deep_copy_children!(dst, src; index=END)

Copy all children of `src` into `dst` at position `index` (1-based, `END` to
append).  Works across different trees.
"""
function deep_copy_children!(dst::YAMLNode, src::YAMLNode; index::Integer=END)
  c_index = index == END ? END : Csize_t(index - 1)
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
