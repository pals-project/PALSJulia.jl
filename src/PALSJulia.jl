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

"""
    export_manipulators()

Export the public functions from yaml_wrapper.jl (Base/Core method extensions
such as getindex, length, keys, ... are intentionally omitted).
"""
function export_manipulators()
  @eval export parse_file
  @eval export parse_string
  @eval export create_empty_tree
  @eval export is_map
  @eval export is_sequence
  @eval export is_scalar
  @eval export get_parent
  @eval export node_key
  @eval export add_scalar!
  @eval export add_map!
  @eval export add_sequence!
  @eval export set_scalar!
  @eval export set_key!
  @eval export remove!
  @eval export deep_copy_node!
  @eval export deep_copy_children!
  @eval export to_yaml_string
  @eval export write_yaml
  return nothing
end

include("structs.jl")
include("yaml_wrapper.jl")
include("toBmad.jl")
include("toSciBmad.jl")


export parse_and_expand_pals, evaluate_pals_expression, node_correspondence, match_names, pals_to_bmad, write_bmad_file, pals_to_scibmad, write_scibmad_file, export_manipulators

end