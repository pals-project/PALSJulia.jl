"""
    PALSJulia

A Julia wrapper around the yaml_c_wrapper C library (rapidyaml backend).

The C API is tree+nodeId-centric: every operation takes a `YAMLTreeHandle`
(opaque pointer to a parsed tree) and a `YAMLNodeId` (index within that tree).

On the Julia side:
  - `YAMLTree`  owns the C tree handle and frees it via a finalizer.
  - `YAMLNode`  is a lightweight value type holding a reference to its parent
                tree (keeping it alive) and the integer node id.
"""
module PALSJulia

include("yaml_wrapper.jl")

end # module PALSJulia
