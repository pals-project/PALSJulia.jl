# Parsing and writing YAML

pals-julia represents a parsed document as a tree of `YAMLNode` values. Each
node knows whether it is a map, a sequence, or a scalar, and supports the
standard Julia collection idioms. The owning `YAMLTree` frees the underlying C
tree automatically when it is garbage-collected, so you never manage memory by
hand.

## Reading

Parse from a file or from a string:

```julia
import pals_julia as pj

root = pj.parse_file("config.pals.yaml")
# or
root = pj.parse_string("""
server:
  host: localhost
  port: 8080
features:
  - auth
  - logging
""")
```

## Navigating the tree

Index maps by key and sequences by (1-based) integer, then convert the leaf
scalar to the Julia type you want:

```julia
host = String(root["server"]["host"])   # "localhost"
port = String(root["server"]["port"])   # "8080"

pj.haskey(root, "features")              # true
pj.length(root["features"])              # 2
pj.keys(root["server"])                  # ["host", "port"]

for item in root["features"]
    println(String(item))                # auth, logging
end
```

Use `is_map`, `is_sequence`, and `is_scalar` to test a node's kind.

## Building and editing

Create an empty document and add maps, sequences, and scalars to it. The
mutating helpers (suffixed with `!`) return the newly created child node:

```julia
root = pj.create_empty_tree()

server = pj.add_map!(root; key = "server")
server["host"] = "localhost"
server["port"] = "8080"

features = pj.add_sequence!(root; key = "features")
pj.add_scalar!(features, "auth")
pj.add_scalar!(features, "logging")
```

Assigning with `node[key] = value` sets (or creates) a scalar child. Other
handy edits include `set_scalar!`, `set_key!`, `remove!`, `copy`, and the
`deep_copy_node!` / `deep_copy_children!` pair for grafting one subtree onto
another.

## Writing

Serialize a node to a string or straight to disk:

```julia
text = pj.to_yaml_string(root)     # YAML as a String
pj.write_yaml(root, "out.pals.yaml")
```

See the **API Reference** (linked in the sidebar) for the full list of functions
and their signatures.
