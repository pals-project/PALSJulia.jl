import Pkg
Pkg.activate(joinpath(@__DIR__, ".."))
import pals_julia as pj

#reading a lattice from a yaml file
yaml_file = abspath(joinpath(@__DIR__, "..", "lattice_files", "ex.pals.yaml"))
node = pj.parse_file(yaml_file)
#printing to terminal
println(pj.to_yaml_string(node))

#type checking
println((pj.is_sequence(node)))

#accessing sequence
seq = pj.getindex(node, 1)
println("the first element is: \n", pj.to_yaml_string(seq))

#accessing map
println("the value at key 'thingB' is: ", pj.to_yaml_string(getindex(seq, "thingB")))

#creating a new node that's a map 
map = pj.create_map()
pj.setvalue!(map, 2, "first")

#creating a new node that's a sequence
sequence = pj.create_sequence()
pj.push!(sequence, "magnet1")
pj.push!(sequence, "")
scalar = pj.create_scalar()
pj.set!(scalar, "magnet2")
pj.set_at_index!(sequence, 1, scalar)

#adding new nodes to lattice
pj.push!(node, map)
pj.push!(node, sequence)

#writing modified lattice file to expand.pals.yaml
file_dest = abspath(joinpath(@__DIR__, "..", "lattice_files", "expand.pals.yaml"))
pj.write_yaml(node, file_dest)
