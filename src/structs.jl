const LIBYAML = joinpath(@__DIR__, "..", "..", "pals-cpp", "build", "libyaml_c_wrapper.dylib")

# ─── constants matching the C header ────────────────────────────────────────
# Sentinel meaning "no node" / "append at the end"; (size_t)-1 in C.
const YAML_NULL_ID = typemax(Csize_t)

# ─── core types ──────────────────────────────────────────────────────────────

"""
    YAMLTree

Owns a C `YAMLTreeHandle`. Freed automatically when the object is GC'd.
Do not use the handle after the tree has been freed.
"""
mutable struct YAMLTree
  handle::Ptr{Cvoid}

  function YAMLTree(handle::Ptr{Cvoid})
    handle == C_NULL && error("Invalid YAML tree handle (C returned NULL)")
    t = new(handle)
    finalizer(t) do tree
      if tree.handle != C_NULL
        @ccall LIBYAML.delete_tree(tree.handle::Ptr{Cvoid})::Cvoid
        tree.handle = C_NULL
      end
    end
    return t
  end
end

#---------------------------------------------------------------------------------------------------

"""
    YAMLNode

A reference to a single node within a `YAMLTree`.  Holding a `YAMLNode` keeps
its parent tree alive.  Node ids are invalidated if the tree is deleted.
"""
struct YAMLNode
  tree::YAMLTree   # keeps the tree alive
  id::Csize_t      # node id within the tree
end

#---------------------------------------------------------------------------------------------------

# Raw C struct returned by parse_and_expand_pals — three tree handles by value.
struct LatticesHandle
  original::Ptr{Cvoid}
  included::Ptr{Cvoid}
  expanded::Ptr{Cvoid}
end

#---------------------------------------------------------------------------------------------------

"""Three representations of a lattice, each as a root `YAMLNode`."""
struct Lattices
  original::YAMLNode
  included::YAMLNode
  expanded::YAMLNode
end
