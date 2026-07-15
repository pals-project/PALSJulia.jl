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

# Two YAMLNodes are equal when they point at the same id in the same tree.
# Defining these lets YAMLNode be used as a Dict key (e.g. in node_correspondence).
Base.:(==)(a::YAMLNode, b::YAMLNode) = (a.tree === b.tree) && (a.id == b.id)
Base.hash(n::YAMLNode, h::UInt) = hash(n.id, hash(objectid(n.tree), h))

#---------------------------------------------------------------------------------------------------

# Raw C struct returned by parse_and_expand_pals — three tree handles by value.
struct LatticesHandle
  original::Ptr{Cvoid}
  combined::Ptr{Cvoid}
  expanded::Ptr{Cvoid}
end

#---------------------------------------------------------------------------------------------------

# Raw C structs for build_correspondence_map. NodeLinkC mirrors `struct node_link`
# and CorrespondenceMapC mirrors `struct correspondence_map` from yaml_c_wrapper.h.
struct NodeLinkC
  original::Csize_t
  combined::Csize_t
  expanded::Csize_t
end

struct CorrespondenceMapC
  links::Ptr{NodeLinkC}
  count::Csize_t
end

#---------------------------------------------------------------------------------------------------

"""Three representations of a lattice, each as a root `YAMLNode`."""
struct Lattices
  original::YAMLNode
  combined::YAMLNode
  expanded::YAMLNode
end
