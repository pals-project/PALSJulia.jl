# pals_julia.jl

Documentation for pals_julia.jl.

## Installation
```julia
# Install from local directory
using Pkg
Pkg.add(path="/path/to/pals_julia.jl")
```

## Quick Example
```julia
import Pkg
Pkg.activate(joinpath(@__DIR__, ".."))
import pals_julia as pj

# Parse YAML
config = parse_yaml("""
server:
  host: localhost
  port: 8080
features:
  - auth
  - logging
""")

# Access values
host = String(config["server"]["host"])  # "localhost"
port = Int(config["server"]["port"])     # 8080

# Create YAML
new_config = create_map()
new_config["name"] = "MyApp"
write_yaml(new_config, "config.pals.yaml")
```
