using Libdl

# Cached path to the pals-cpp shared library; empty until first resolved by
# libyaml(). A Ref rather than a const String so the path is read at call time
# rather than frozen into the precompile cache, which keeps the cache valid
# across machines and lets the environment variables below take effect without
# a forced recompile.
const LIBYAML = Ref{String}("")

# Every place the library might be. The library is built by pals-cpp and is not
# shipped with this package, so it has to be searched for. In order:
#   1. $PALS_CPP_LIB — full path to the shared library itself
#   2. $PALS_CPP_DIR — a pals-cpp checkout; its build directory is searched
#   3. a pals-cpp checkout beside this one (the layout the installation guide
#      describes)
function _libyaml_candidates()
  # dlext is "dylib" on macOS, "so" on Linux, "dll" on Windows. MSVC drops the
  # "lib" prefix and writes into a per-configuration subdirectory; the
  # single-config generators used elsewhere write straight into build/.
  names = ("libyaml_c_wrapper.$(Libdl.dlext)", "yaml_c_wrapper.$(Libdl.dlext)")
  subdirs = ("", "Release", "Debug")

  out = String[]
  haskey(ENV, "PALS_CPP_LIB") && push!(out, ENV["PALS_CPP_LIB"])

  roots = String[]
  haskey(ENV, "PALS_CPP_DIR") && push!(roots, ENV["PALS_CPP_DIR"])
  push!(roots, normpath(joinpath(@__DIR__, "..", "..", "pals-cpp")))

  for r in roots, s in subdirs, n in names
    push!(out, normpath(joinpath(r, "build", s, n)))
  end
  return out
end

# Locate the library, or explain exactly what was looked for and how to fix it.
function _find_libyaml()
  candidates = _libyaml_candidates()
  for c in candidates
    isfile(c) && return c
  end
  error("""
        PALSJulia could not find the pals-cpp shared library \
        (libyaml_c_wrapper.$(Libdl.dlext)).

        Build it from a pals-cpp checkout:
            cmake -S . -B build && cmake --build build

        Then either clone pals-cpp next to PALSJulia, or point PALSJulia at it:
            ENV["PALS_CPP_DIR"] = "/path/to/pals-cpp"
            ENV["PALS_CPP_LIB"] = "/path/to/libyaml_c_wrapper.$(Libdl.dlext)"

        Searched:
        """ * join("  " .* candidates, "\n"))
end

"""
    PALSJulia.libyaml() -> String

Absolute path to the pals-cpp shared library every `@ccall` here targets,
resolved on first use and cached thereafter. Throws a descriptive error listing
every path tried if the library cannot be found.

Resolution is deliberately lazy rather than done in `__init__`: `using
PALSJulia` must succeed without the C library present, so that documentation and
other tooling can read the package without a C++ toolchain. The cost is that a
missing library is reported at the first call rather than at load.
"""
function libyaml()
  isempty(LIBYAML[]) && (LIBYAML[] = _find_libyaml())
  return LIBYAML[]
end

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
        @ccall (libyaml()).delete_tree(tree.handle::Ptr{Cvoid})::Cvoid
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

# Raw C struct mirroring `struct string_list` from yaml_c_wrapper.h: an owning
# array of C strings and its length. Carries the problems found while building
# the expanded tree; freed with free_lattice_problems.
struct StringListC
  items::Ptr{Cstring}
  count::Csize_t
end

# Raw C struct returned by parse_and_expand_pals — four tree handles plus the
# problem list, all by value. Layout must match `struct lattices`.
struct LatticesHandle
  original::Ptr{Cvoid}
  combined::Ptr{Cvoid}
  expanded::Ptr{Cvoid}
  leftover::Ptr{Cvoid}
  problems::StringListC
end

#---------------------------------------------------------------------------------------------------

# Raw C structs for build_correspondence_map. NodeLinkC mirrors `struct node_link`
# and CorrespondenceMapC mirrors `struct correspondence_map` from yaml_c_wrapper.h.
struct NodeLinkC
  original::Csize_t
  combined::Csize_t
  expanded::Csize_t
  leftover::Csize_t
end

struct CorrespondenceMapC
  links::Ptr{NodeLinkC}
  count::Csize_t
end

#---------------------------------------------------------------------------------------------------

# Raw C struct for match_names. Mirrors `struct name_matches` from
# yaml_c_wrapper.h: a flat array of matched node ids and its length.
struct NameMatchesC
  nodes::Ptr{Csize_t}
  count::Csize_t
end

#---------------------------------------------------------------------------------------------------

# Raw C struct returned by parameter_value. Mirrors `struct param_value`
# from yaml_c_wrapper.h. `kind` is one of the PARAM_VALUE_* constants below;
# `number` is meaningful when kind is PARAM_VALUE_NUMBER; `string` is an owning C
# string (freed with yaml_free_string) when kind is PARAM_VALUE_STRING, else
# NULL. The Cint/Cdouble/Cstring layout, with padding after `kind`, matches the
# C `int`/`double`/`char*` struct.
struct ParamValueC
  kind::Cint
  number::Cdouble
  string::Cstring
end

# `enum param_value_kind` from yaml_c_wrapper.h.
const PARAM_VALUE_MISSING = Cint(0)
const PARAM_VALUE_NUMBER = Cint(1)
const PARAM_VALUE_STRING = Cint(2)

#---------------------------------------------------------------------------------------------------

"""
Four representations of a lattice, each as a root `YAMLNode`, plus the list of
problems found while expanding it.

`problems` is a `Vector{String}` — one human-readable message per problem
encountered during expansion (undefined lattice, dangling element/line
references, undefined `inherit`/`repeat`/`Fork` targets, and expressions that
could not be evaluated). It is empty when expansion was clean.
"""
struct Lattices
  original::YAMLNode
  combined::YAMLNode
  expanded::YAMLNode
  leftover::YAMLNode
  problems::Vector{String}
end
