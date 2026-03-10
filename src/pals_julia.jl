"""
    pals-julia

A Julia wrapper around yaml-cpp's YAML::Node.

Represents a YAML document node that can be a scalar, map, or sequence.

"""
module pals_julia
const LIBYAML = joinpath(@__DIR__, "..", "..", "pals-cpp", "build", "libyaml_c_wrapper.dylib")
#julia precompilation failing, can tell julia to skip precompilation for this part
# Opaque handle type
mutable struct YAMLNode
    handle::Ptr{Cvoid}
    
    function YAMLNode(handle::Ptr{Cvoid})
        if handle == C_NULL
            error("Invalid YAML node handle")
        end
        node = new(handle)
        finalizer(delete_node, node)
        return node
    end
end

struct LatticesHandle
    original::Ptr{Cvoid}
    included::Ptr{Cvoid}
    expanded::Ptr{Cvoid}
end

# The user-facing Julia struct holding the safe wrappers
struct Lattices
    original::YAMLNode
    included::YAMLNode
    expanded::YAMLNode
end

"""
    get_lattices(filename::String, lattice_name::String="") -> Lattices

Parses a lattice file and returns the original, included, and expanded lattice nodes.
"""
function get_lattices(filename::String, lattice_name::String="")
    # Check if file exists first to prevent segfaults
    if !isfile(filename)
        error("File not found: $filename")
    end

    # Call the C library. It returns the struct by value.
    handles = @ccall LIBYAML.get_lattices(
        filename::Cstring, 
        lattice_name::Cstring
    )::LatticesHandle

    # Check for NULL pointers just in case parsing failed completely
    if handles.original == C_NULL || handles.included == C_NULL || handles.expanded == C_NULL
        error("Failed to parse or expand the lattice file: $filename")
    end

    # Wrap the raw C pointers in your safe Julia objects
    return Lattices(
        YAMLNode(handles.original),
        YAMLNode(handles.included),
        YAMLNode(handles.expanded)
    )
end

# === CREATION ===
function create_node()
    handle = @ccall LIBYAML.create_node()::Ptr{Cvoid}
    return YAMLNode(handle)
end

function create_map()
    handle = @ccall LIBYAML.create_map()::Ptr{Cvoid}
    return YAMLNode(handle)
end

function create_sequence()
    handle = @ccall LIBYAML.create_sequence()::Ptr{Cvoid}
    return YAMLNode(handle)
end

function create_scalar()
    handle = @ccall LIBYAML.create_scalar()::Ptr{Cvoid}
    return YAMLNode(handle)
end

function delete_node(node::YAMLNode)
    if node.handle != C_NULL
        @ccall LIBYAML.delete_node(node.handle::Ptr{Cvoid})::Cvoid
        node.handle = C_NULL
    end
end

# === PARSING ===
function parse_yaml(yaml_str::String)
    handle = @ccall LIBYAML.parse_string(yaml_str::Cstring)::Ptr{Cvoid}
    return YAMLNode(handle)
end

function parse_file(filename::String)
    # Check if file exists first
    if !isfile(filename)
        error("File not found: $filename")
    end
    
    handle = @ccall LIBYAML.parse_file(filename::Cstring)::Ptr{Cvoid}
    
    if handle == C_NULL
        error("Failed to parse YAML file: $filename (C library returned NULL)")
    end
    
    return YAMLNode(handle)
end

# === TYPE CHECKS ===
function is_scalar(node::YAMLNode)
    @ccall LIBYAML.is_scalar(node.handle::Ptr{Cvoid})::Bool
end

function is_sequence(node::YAMLNode)
    @ccall LIBYAML.is_sequence(node.handle::Ptr{Cvoid})::Bool
end

function is_map(node::YAMLNode)
    @ccall LIBYAML.is_map(node.handle::Ptr{Cvoid})::Bool
end

function is_null(node::YAMLNode)
    @ccall LIBYAML.is_null(node.handle::Ptr{Cvoid})::Bool
end

# === ACCESS ===
function Base.getindex(node::YAMLNode, key::String)
    handle = @ccall LIBYAML.get_key(node.handle::Ptr{Cvoid}, key::Cstring)::Ptr{Cvoid}
    handle == C_NULL && error("Key not found: $key")
    return YAMLNode(handle)
end

function Base.getindex(node::YAMLNode, index::Int)
    handle = @ccall LIBYAML.get_index(node.handle::Ptr{Cvoid}, (index-1)::Cint)::Ptr{Cvoid}
    handle == C_NULL && error("Index out of bounds: $index")
    return YAMLNode(handle)
end

function Base.haskey(node::YAMLNode, key::String)
    @ccall LIBYAML.has_key(node.handle::Ptr{Cvoid}, key::Cstring)::Bool
end

function Base.length(node::YAMLNode)
    @ccall LIBYAML.size(node.handle::Ptr{Cvoid})::Cint
end

# === CONVERT TO JULIA TYPES ===
function Base.String(node::YAMLNode)
    ptr = @ccall LIBYAML.as_string(node.handle::Ptr{Cvoid})::Cstring
    if ptr == C_NULL
        error("Cannot convert node to string")
    end
    str = unsafe_string(ptr)
    @ccall LIBYAML.yaml_free_string(ptr::Cstring)::Cvoid
    return str
end

function Base.Int(node::YAMLNode)
    @ccall LIBYAML.as_int(node.handle::Ptr{Cvoid})::Cint
end

function Base.Float64(node::YAMLNode)
    @ccall LIBYAML.as_float(node.handle::Ptr{Cvoid})::Cdouble
end

function Base.Bool(node::YAMLNode)
    @ccall LIBYAML.as_bool(node.handle::Ptr{Cvoid})::Bool
end

# === MODIFICATION ===
function setvalue!(node::YAMLNode, value::String, key::String)
    @ccall LIBYAML.set_value_string(node.handle::Ptr{Cvoid}, key::Cstring, value::Cstring)::Cvoid
end

function setvalue!(node::YAMLNode, value::Int, key::String)
    @ccall LIBYAML.set_value_int(node.handle::Ptr{Cvoid}, key::Cstring, value::Cint)::Cvoid
end

function setvalue!(node::YAMLNode, value::Float64, key::String)
    @ccall LIBYAML.set_value_float(node.handle::Ptr{Cvoid}, key::Cstring, value::Cdouble)::Cvoid
end

function setvalue!(node::YAMLNode, value::Bool, key::String)
    @ccall LIBYAML.set_value_bool(node.handle::Ptr{Cvoid}, key::Cstring, value::Bool)::Cvoid
end

function setvalue!(node::YAMLNode, value::YAMLNode, key::String)
    @ccall LIBYAML.set_value_node(node.handle::Ptr{Cvoid}, key::Cstring, value.handle::Ptr{Cvoid})::Cvoid
end

function set!(node::YAMLNode, string::String)
    @ccall LIBYAML.set_scalar_string(node.handle::Ptr{Cvoid}, string::Cstring)::Cvoid
end

function set!(node::YAMLNode, int::Int)
    @ccall LIBYAML.set_scalar_int(node.handle::Ptr{Cvoid}, int::Cint)::Cvoid
end

function set!(node::YAMLNode, float::Float64)
    @ccall LIBYAML.set_scalar_float(node.handle::Ptr{Cvoid}, float::Cdouble)::Cvoid
end

function set!(node::YAMLNode, bool::Bool)
    @ccall LIBYAML.set_scalar_bool(node.handle::Ptr{Cvoid}, bool::Bool)::Cvoid
end

function set_at_index!(node::YAMLNode, index::Int, value::YAMLNode)
    @ccall LIBYAML.set_at_index(node.handle::Ptr{Cvoid}, index::Cint, value.handle::Ptr{Cvoid})::Cvoid
end

function Base.push!(node::YAMLNode, value::String)
    @ccall LIBYAML.push_string(node.handle::Ptr{Cvoid}, value::Cstring)::Cvoid
end

function Base.push!(node::YAMLNode, value::Int)
    @ccall LIBYAML.push_int(node.handle::Ptr{Cvoid}, value::Cint)::Cvoid
end

function Base.push!(node::YAMLNode, value::Float64)
    @ccall LIBYAML.push_float(node.handle::Ptr{Cvoid}, value::Cdouble)::Cvoid
end

function Base.push!(node::YAMLNode, value::YAMLNode)
    @ccall LIBYAML.push_node(node.handle::Ptr{Cvoid}, value.handle::Ptr{Cvoid})::Cvoid
end

# === WRITE TO FILE WITH EMITTER (CORRECTED) ===

"""
    write_yaml(node::YAMLNode, filename::String) -> Bool

Write a YAML node to a file using an emitter with default formatting.
"""
function write_yaml(node::YAMLNode, filename::String)
    success = @ccall LIBYAML.write_file(
        node.handle::Ptr{Cvoid}, 
        filename::Cstring
    )::Bool
    return success
end

"""
    write_yaml(node::YAMLNode, filename::String; 
               indent=2, flow_maps=false, flow_seqs=false) -> Bool

Write a YAML node to a file with emitter control.

# Arguments
- `indent`: Number of spaces for indentation (default: 2)
- `flow_maps`: Use flow style {key: value} for maps (default: false)
- `flow_seqs`: Use flow style [item1, item2] for sequences (default: false)
"""
function write_yaml_formatted(node::YAMLNode, filename::String; 
                   indent::Int=2, 
                   flow_maps::Bool=false,
                   flow_seqs::Bool=false)
    success = @ccall LIBYAML.write_file_formatted(
        node.handle::Ptr{Cvoid}, 
        filename::Cstring,
        indent::Cint,
        flow_maps::Bool,
        flow_seqs::Bool
    )::Bool
    return success
end

"""
    write_yaml_advanced(node::YAMLNode, filename::String; options...) -> Bool

Write a YAML node to a file with full formatting control.

# Arguments
- `indent`: Number of spaces for indentation (default: 2)
- `flow_maps`: Use flow style for maps (default: false)
- `flow_seqs`: Use flow style for sequences (default: false)
- `bool_format`: Boolean format - :yesno, :truefalse, or :onoff (default: :truefalse)
- `null_format`: Null format - :tilde (~), :lower (null), :upper (NULL), or :camel (Null) (default: :lower)
- `string_format`: String format - :auto, :single, :double, or :literal (default: :auto)
"""
function write_yaml_advanced(node::YAMLNode, filename::String;
                            indent::Int=2,
                            flow_maps::Bool=false,
                            flow_seqs::Bool=false,
                            bool_format::Symbol=:truefalse,
                            null_format::Symbol=:lower,
                            string_format::Symbol=:auto)
    
    bool_fmt = bool_format == :yesno ? 0 : bool_format == :truefalse ? 1 : 2
    null_fmt = null_format == :tilde ? 0 : null_format == :lower ? 1 : 
               null_format == :upper ? 2 : 3
    str_fmt = string_format == :auto ? 0 : string_format == :single ? 1 :
              string_format == :double ? 2 : 3
    
    success = @ccall LIBYAML.write_file_advanced(
        node.handle::Ptr{Cvoid},
        filename::Cstring,
        indent::Cint,
        flow_maps::Bool,
        flow_seqs::Bool,
        bool_fmt::Cint,
        null_fmt::Cint,
        str_fmt::Cint
    )::Bool
    
    return success
end

"""
    emit_yaml(node::YAMLNode; indent=2) -> String

Convert a YAML node to a formatted string using an emitter.
"""
function emit_yaml(node::YAMLNode; indent::Int=2)
    ptr = @ccall LIBYAML.yaml_emit(
        node.handle::Ptr{Cvoid},
        indent::Cint
    )::Cstring
    
    if ptr == C_NULL
        error("Failed to emit YAML")
    end
    
    str = unsafe_string(ptr)
    @ccall LIBYAML.yaml_free_string(ptr::Cstring)::Cvoid
    return str
end

# === UTILITY ===
function to_yaml_string(node::YAMLNode)
    ptr = @ccall LIBYAML.yaml_to_string(node.handle::Ptr{Cvoid})::Cstring
    if ptr == C_NULL
        error("Cannot convert node to YAML string")
    end
    str = unsafe_string(ptr)
    @ccall LIBYAML.yaml_free_string(ptr::Cstring)::Cvoid
    return str
end

Base.show(io::IO, node::YAMLNode) = print(io, "YAMLNode(...)")

function clone(node::YAMLNode)
    handle = @ccall LIBYAML.yaml_clone(node.handle::Ptr{Cvoid})::Ptr{Cvoid}
    return YAMLNode(handle)
end

end