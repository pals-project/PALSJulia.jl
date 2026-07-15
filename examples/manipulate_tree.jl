# Example that reads in a PALS file and then manipulates the resulting tree structure in memory.

using PALSJulia
import PALSJulia as pj

lattice_dir = joinpath(@__DIR__, "..", "lattice_files")
ex_file      = joinpath(lattice_dir, "ex.pals.yaml")
expand_file  = joinpath(lattice_dir, "expand.pals.yaml")

println("============ Printing Developer Information ============")

# reading a lattice from a yaml file
println("""Use the function 'tree = parse_file(filename)' to read a YAML file.
           This reads in any YAML file. To read in a PALS file with lattice expansion,
           use the function parse_and_expand_pals.""")

tree = pj.parse_file(ex_file)

# printing to terminal
println("To print a tree to console, use the 'pj.to_yaml_string(tree_name)' function.")
println(pj.to_yaml_string(tree), "\n")

# type checking
println("The root node of 'ex.pals.yaml' is the 'PALS' map, so is_map(tree) = ",
         pj.is_map(tree))

# The lattice contents live under the 'facility' node of the 'PALS' root.
facility = tree["PALS"]["facility"]
println("The 'facility' node is a sequence, so is_sequence(facility) = ",
         pj.is_sequence(facility))

# accessing sequence
println("Elements in a sequence may be accessed by their index.")
first_ele = facility[1]
println("The first element of 'facility' is: \n", pj.to_yaml_string(first_ele))

# accessing map
println("Elements in a map may be accessed by their key.")
a_const = first_ele["constants"]["a_const"]
println("The 'a_const' constant has the value:\n    ", pj.to_yaml_string(a_const))

# add a new sequence element to the facility containing new_map: {apples: 5}
println("Adding a new element '-apples: 5' to facility.")
new_map_entry = pj.add_map!(facility)
map_node = pj.add_map!(new_map_entry, key="new_map")
pj.add_scalar!(map_node, "5", key="apples")

# add a new sequence element to the facility containing magnets
println("Adding a new element")
println("    - magnet_list:")
println("        - magnet1")
println("        - magnet2")
println("to facility.\n")
magnets_entry = pj.add_map!(facility)
sequence = pj.add_sequence!(magnets_entry, key="magnet_list")
pj.add_scalar!(sequence, "magnet1")
pj.add_scalar!(sequence, "magnet2", index=1)

# writing trees to files
println("Use 'write_yaml(tree, filename)' to write the edited tree to a file.")
pj.write_yaml(tree, expand_file)
println("Wrote tree to 'expand.pals.yaml'\n\n\n")

println("========== Printing Final Modified Tree ==========")
println(pj.to_yaml_string(tree))
