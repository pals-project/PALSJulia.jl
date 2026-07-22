# Parsing and writing YAML

PALSJulia represents a parsed document as a tree of `YAMLNode` values. Each
node knows whether it is a map, a sequence, or a scalar, and supports the
standard Julia collection idioms. The owning `YAMLTree` frees the underlying C
tree automatically when it is garbage-collected, so you never manage memory by
hand.

## Making the functions available

`using PALSJulia` on its own brings only a handful of names into scope. The
tree-manipulation functions documented below live in the package but are not
exported by default. Call `export_manipulators()` once to export them so they
can be used by their bare names:

```julia
using PALSJulia
export_manipulators()

root = parse_file("config.pals.yaml")
```

If you would rather **not** pull those extra symbols into your namespace, skip
`export_manipulators()` and instead import the package under an alias:

```julia
import PALSJulia as pj

root = pj.parse_file("config.pals.yaml")
```

and prefix each call, e.g. `pj.parse_file(...)`. The rest of this guide assumes
you have called `export_manipulators()` and uses bare names throughout.

## Reading

Parse from a file or from a string. Both return a `YAMLNode` pointing at the
tree root:

| Function | Description |
| --- | --- |
| `parse_file(filename)` | Parse a YAML file from disk. |
| `parse_string(yaml_str)` | Parse YAML from a string. |
| `create_empty_tree()` | Create a new, empty MAP tree to build up from scratch. |
| `parse_and_expand_pals(filename, root_lattice="")` | Parse a PALS lattice file and return original, combined, expanded and leftover views. |

```julia
root = parse_file("config.pals.yaml")
# or
root = parse_string("""
server:
  host: localhost
  port: 8080
features:
  - auth
  - logging
""")
```

`parse_and_expand_pals` is PALS-specific: it returns a `Lattices` value holding
four independent tree views (`original`, `combined`, `expanded`, `leftover`),
each freed on its own when garbage-collected.

## Querying the tree

Use these functions to inspect a node's kind, walk the tree, and read out its
structure. None of them modify the document.

### Kind checks

Every node is exactly one of map, sequence, or scalar:

| Function | Description |
| --- | --- |
| `is_map(node)` | `true` if `node` is a map (key/value pairs). |
| `is_sequence(node)` | `true` if `node` is a sequence (ordered list). |
| `is_scalar(node)` | `true` if `node` is a scalar leaf value. |

### Navigation and inspection

| Function | Description |
| --- | --- |
| `node[key]` | The direct child of a map `node` under string `key` (errors if absent). |
| `node[index]` | The `index`-th child (1-based) of a map or sequence. |
| `haskey(node, key)` | `true` if the map `node` has a direct child under `key`. |
| `length(node)` | Number of direct children (0 for a scalar). |
| `keys(node)` | The keys of a map `node`, in order, as a `Vector{String}`. |
| `node_key(node)` | The key `node` is stored under in its parent, or `nothing`. |
| `get_parent(node)` | The parent node (errors if `node` is the root). |
| `eachindex(node)` | Index range for iterating a map or sequence. |
| `iterate(node)` | Enables `for` loops: sequences yield elements, maps yield `(key, node)` pairs. |

```julia
haskey(root, "features")          # true
length(root["features"])          # 2
keys(root["server"])              # ["host", "port"]

for item in root["features"]
    println(String(item))         # auth, logging
end

for (k, v) in root["server"]
    println(k, " => ", String(v)) # host => localhost, port => 8080
end

parent = get_parent(root["server"])   # back up to the root
```

### Reading scalar values

Convert a scalar leaf node to the Julia type you want:

| Function | Description |
| --- | --- |
| `String(node)` | The scalar value as a `String` (the raw text). |
| `Int(node)` | The scalar parsed as an `Int`. |
| `Float64(node)` | The scalar parsed as a `Float64`. |
| `Bool(node)` | The scalar parsed as a `Bool` (`"true"` / `"false"`). |

```julia
host = String(root["server"]["host"])   # "localhost"
port = Int(root["server"]["port"])       # 8080
```

## Building and editing

Create an empty document and add maps, sequences, and scalars to it. The
mutating helpers (suffixed with `!`) return the newly created child node:

| Function | Description |
| --- | --- |
| `add_scalar!(parent, value; key=nothing, index=nothing)` | Add a scalar child. |
| `add_map!(parent; key=nothing, index=nothing)` | Add an empty map child. |
| `add_sequence!(parent; key=nothing, index=nothing)` | Add an empty sequence child. |
| `node[key] = value` | Set (or create) a scalar child under `key`. |
| `set_scalar!(node, value)` | Set or replace a node's scalar value in place. |
| `set_key!(node, key)` | Set or replace the key a node is stored under. |
| `remove!(node)` | Remove a node and all its descendants. |
| `copy(node)` | An independent deep copy of `node` in a new tree. |
| `deep_copy_node!(dst, src)` | Overwrite `dst` with a deep copy of `src`. |
| `deep_copy_children!(dst, src; index=nothing)` | Copy all children of `src` into `dst`. |

Pass `key` for map children and omit it (or pass `nothing`) for sequence
elements. `index` selects the 1-based position among the existing children; it
defaults to `nothing`, which appends at the end, so you usually leave it out.

```julia
root = create_empty_tree()

server = add_map!(root; key = "server")
server["host"] = "localhost"
server["port"] = "8080"

features = add_sequence!(root; key = "features")
add_scalar!(features, "auth")
add_scalar!(features, "logging")
```

The `deep_copy_node!` / `deep_copy_children!` pair works across different trees,
so you can graft one subtree onto another.

## Writing

Serialize a node to a string or straight to disk:

| Function | Description |
| --- | --- |
| `to_yaml_string(node; exclude)` | The node and its descendants as a YAML `String`. |
| `write_yaml(node, filename; exclude)` | Write the whole tree containing `node` to a file. |

```julia
text = to_yaml_string(root)     # YAML as a String
write_yaml(root, "out.pals.yaml")
```

Both take an `exclude` keyword naming keys to leave out, which is handy for
printing or saving a large lattice without the bulky subtrees.  Every MAP entry
with a matching key is dropped, at any depth, together with its subtree; the
tree in memory is not modified.

```julia
println(to_yaml_string(root, exclude = ["FloorP", "ReferenceP"]))
println(to_yaml_string(root, exclude = "FloorP"))   # a single key needs no vector
write_yaml(root, "out.pals.yaml", exclude = ["FloorP", "ReferenceP"])
```

See the **API Reference** (linked in the sidebar) for the full list of functions
and their signatures.
