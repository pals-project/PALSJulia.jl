using Libdl

# Cached path to the PALSParserCpp shared library; empty until first resolved by
# libparser(). A Ref rather than a const String so the path is read at call time
# rather than frozen into the precompile cache, which keeps the cache valid
# across machines and lets the environment variables below take effect without
# a forced recompile.
const LIBPARSER = Ref{String}("")

# Every place the library might be. The library is built by PALSParserCpp and is
# not shipped with this package, so it has to be searched for. In order:
#   1. $PALS_PARSER_CPP_LIB — full path to the shared library itself
#   2. $PALS_PARSER_CPP_DIR — a PALSParserCpp checkout; its build directory is
#      searched
#   3. a PALSParserCpp checkout beside this one (the layout the installation
#      guide describes)
function _libparser_candidates()
  # dlext is "dylib" on macOS, "so" on Linux, "dll" on Windows. MSVC drops the
  # "lib" prefix and writes into a per-configuration subdirectory; the
  # single-config generators used elsewhere write straight into build/.
  names = ("libPALSParserCpp.$(Libdl.dlext)", "PALSParserCpp.$(Libdl.dlext)")
  subdirs = ("", "Release", "Debug")

  out = String[]
  haskey(ENV, "PALS_PARSER_CPP_LIB") && push!(out, ENV["PALS_PARSER_CPP_LIB"])

  roots = String[]
  haskey(ENV, "PALS_PARSER_CPP_DIR") && push!(roots, ENV["PALS_PARSER_CPP_DIR"])
  push!(roots, normpath(joinpath(@__DIR__, "..", "..", "PALSParserCpp")))

  for r in roots, s in subdirs, n in names
    push!(out, normpath(joinpath(r, "build", s, n)))
  end
  return out
end

# Locate the library, or explain exactly what was looked for and how to fix it.
function _find_libparser()
  candidates = _libparser_candidates()
  for c in candidates
    isfile(c) && return c
  end
  error("""
        PALSParserJ could not find the PALSParserCpp shared library \
        (libPALSParserCpp.$(Libdl.dlext)).

        Build it from a PALSParserCpp checkout:
            cmake -S . -B build && cmake --build build

        Then either clone PALSParserCpp next to PALSParserJ, or point \
        PALSParserJ at it:
            ENV["PALS_PARSER_CPP_DIR"] = "/path/to/PALSParserCpp"
            ENV["PALS_PARSER_CPP_LIB"] = "/path/to/libPALSParserCpp.$(Libdl.dlext)"

        Searched:
        """ * join("  " .* candidates, "\n"))
end

"""
    PALSParserJ.libparser() -> String

Absolute path to the PALSParserCpp shared library every `@ccall` here targets,
resolved on first use and cached thereafter. Throws a descriptive error listing
every path tried if the library cannot be found.

Resolution is deliberately lazy rather than done in `__init__`: `using
PALSParserJ` must succeed without the C library present, so that documentation
and other tooling can read the package without a C++ toolchain. The cost is that
a missing library is reported at the first call rather than at load.
"""
function libparser()
  isempty(LIBPARSER[]) && (LIBPARSER[] = _find_libparser())
  return LIBPARSER[]
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
        @ccall (libparser()).delete_tree(tree.handle::Ptr{Cvoid})::Cvoid
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

"""
Whether a problem leaves the expanded trees trustworthy.

- `PROBLEM_ERROR` — the document is wrong here and expansion could not work
  around it. Do not trust the affected part of the trees.
- `PROBLEM_WARNING` — expansion produced a usable result; something was assumed
  or skipped, but the trees are still sound.

Mirrors `enum problem_severity` in PALSParserCpp.h.
"""
@enum ProblemSeverity::Cint PROBLEM_ERROR = 0 PROBLEM_WARNING = 1

"""
Who has to act on a problem.

- `PROBLEM_INPUT` — the document is wrong; the lattice author can fix it.
- `PROBLEM_UNSUPPORTED` — valid PALS that PALSParserCpp does not implement yet.
  Editing the lattice will not clear it.
- `PROBLEM_UNSPECIFIED` — the PALS standard does not define the case, so nothing
  was invented. Neither the author nor the library is in the wrong.

Mirrors `enum problem_origin` in PALSParserCpp.h.
"""
@enum ProblemOrigin::Cint PROBLEM_INPUT = 0 PROBLEM_UNSUPPORTED = 1 PROBLEM_UNSPECIFIED = 2

# Raw C struct mirroring `struct problem` from PALSParserCpp.h. Both strings are
# owned by the C side and are freed with free_lattice_problems; the two enums are
# C `int`s. Layout must match field for field and in order.
struct ProblemC
  message::Cstring
  path::Cstring
  severity::Cint
  origin::Cint
end

# Raw C struct mirroring `struct problem_list`: an owning array of ProblemC and
# its length. Carries the problems found while building the full_expanded tree;
# freed with free_lattice_problems.
struct ProblemListC
  items::Ptr{ProblemC}
  count::Csize_t
end

# Raw C struct returned by parse_and_expand_pals — five tree handles plus the
# problem list, all by value. Layout must match `struct lattices`, field for
# field and in order.
struct LatticesHandle
  original::Ptr{Cvoid}
  combined::Ptr{Cvoid}
  expanded::Ptr{Cvoid}
  full_expanded::Ptr{Cvoid}
  adjunct::Ptr{Cvoid}
  problems::ProblemListC
end

#---------------------------------------------------------------------------------------------------

# Raw C structs for build_correspondence_map. NodeLinkC mirrors `struct
# node_link` and CorrespondenceMapC mirrors `struct correspondence_map` from
# PALSParserCpp.h.
struct NodeLinkC
  original::Csize_t
  combined::Csize_t
  full_expanded::Csize_t
  adjunct::Csize_t
end

struct CorrespondenceMapC
  links::Ptr{NodeLinkC}
  count::Csize_t
end

#---------------------------------------------------------------------------------------------------

# Raw C struct for match_names. Mirrors `struct name_matches` from
# PALSParserCpp.h: a flat array of matched node ids and its length.
struct NameMatchesC
  nodes::Ptr{Csize_t}
  count::Csize_t
end

#---------------------------------------------------------------------------------------------------

# Raw C struct returned by parameter_value. Mirrors `struct param_value`
# from PALSParserCpp.h. `kind` is one of the PARAM_VALUE_* constants below;
# `number` is meaningful when kind is PARAM_VALUE_NUMBER; `string` is an owning C
# string (freed with yaml_free_string) when kind is PARAM_VALUE_STRING, else
# NULL. The Cint/Cdouble/Cstring layout, with padding after `kind`, matches the
# C `int`/`double`/`char*` struct.
struct ParamValueC
  kind::Cint
  number::Cdouble
  string::Cstring
end

# `enum param_value_kind` from PALSParserCpp.h.
const PARAM_VALUE_MISSING = Cint(0)
const PARAM_VALUE_NUMBER = Cint(1)
const PARAM_VALUE_STRING = Cint(2)

#---------------------------------------------------------------------------------------------------

"""
One problem found while reading or expanding a document.

- `message` — human-readable description, always present.
- `path` — the logical spot it was found at, such as `"q1>ApertureP.shape"`.
  Empty when the problem is not tied to one place. This is a location within the
  document, not a file name or a line number; `message` already names the file
  where the file is the point.
- `severity` — a [`ProblemSeverity`](@ref): can the trees still be trusted?
- `origin` — a [`ProblemOrigin`](@ref): whose problem is it?

Only a `PROBLEM_INPUT` can be cleared by editing the lattice, which is what makes
the last field worth reading: a tool that fails on any problem at all will fail
on lattices whose author has nothing left to fix.
"""
struct Problem
  message::String
  path::String
  severity::ProblemSeverity
  origin::ProblemOrigin
end

function Base.show(io::IO, p::Problem)
  print(io, p.severity === PROBLEM_ERROR ? "ERROR" : "WARNING")
  p.origin === PROBLEM_UNSUPPORTED && print(io, " (unsupported)")
  p.origin === PROBLEM_UNSPECIFIED && print(io, " (unspecified by PALS)")
  isempty(p.path) || print(io, " at ", p.path)
  print(io, ": ", p.message)
end

"""
Five representations of a lattice, each as a root `YAMLNode`, plus the list of
problems found while expanding it.

`expanded` and `full_expanded` are the same expanded lattice holding the same
values; `full_expanded` additionally carries every parameter the bookkeeper
computed, while `expanded` keeps only what the author wrote. See
[`parse_and_expand_pals`](@ref) for what each view holds.

`problems` is a `Vector{`[`Problem`](@ref)`}` — one entry per problem
encountered during expansion (undefined lattice, dangling element/line
references, undefined `inherit`/`repeat`/`Fork` targets, misspelled names, and
expressions that could not be evaluated). It is empty when expansion was clean.
Filter it on `severity` or `origin` to decide what is worth acting on:

```julia
lat = parse_and_expand_pals("ex.pals.yaml"; problems = :none)
mine = filter(p -> p.origin === PROBLEM_INPUT, lat.problems)
```
"""
struct Lattices
  original::YAMLNode
  combined::YAMLNode
  expanded::YAMLNode
  full_expanded::YAMLNode
  adjunct::YAMLNode
  problems::Vector{Problem}
end
