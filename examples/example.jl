import Pkg
Pkg.activate(joinpath(@__DIR__, ".."))
import PALSJulia as pj

function main()
  lattice_dir = joinpath(@__DIR__, "..", "lattice_files")
  ex_file      = joinpath(lattice_dir, "ex.pals.yaml")
  expand_file  = joinpath(lattice_dir, "expand.pals.yaml")

  println("============ Printing Developer Information ============")

  text = "Use the function 'parse_file(filename)' to read a lattice file. For example,\n" *
         "tree = pj.parse_file(\"../lattice_files/ex.pals.yaml\")\n" *
         "reads the file 'ex.pals.yaml' into a tree named 'tree'.\n\n"

  # reading a lattice from a yaml file
  print(text)
  tree = pj.parse_file(ex_file)

  # printing to terminal
  println("To print a tree to console, use the 'to_yaml_string(tree_name)' function.")
  println(pj.to_yaml_string(tree), "\n")

  # type checking
  println("The root node of 'ex.pals.yaml' is a sequence, so is_sequence(tree) = ",
           pj.is_sequence(tree))

  # accessing sequence
  println("Elements in a sequence may be accessed by their index.")
  seq1 = tree[1]
  println("The first element of 'tree' is: \n", pj.to_yaml_string(seq1))

  # accessing map
  println("Elements in a map may be accessed by their key.")
  map1 = seq1[1]["kind"]
  println("The element 'thingB' has:\n    ", pj.to_yaml_string(map1))

  # add a new sequence element to the root containing new_map: {apples: 5}
  println("Adding a new element '-apples: 5' to root.")
  new_map_entry = pj.add_map!(tree)
  map_node = pj.add_map!(new_map_entry, key="new_map")
  pj.add_scalar!(map_node, "5", key="apples")

  # add a new sequence element to the root containing magnets
  println("Adding a new element")
  println("    - magnet_list:")
  println("        - magnet1")
  println("        - magnet2")
  println("to root.\n")
  magnets_entry = pj.add_map!(tree)
  sequence = pj.add_sequence!(magnets_entry, key="magnet_list")
  pj.add_scalar!(sequence, "magnet1")
  pj.add_scalar!(sequence, "magnet2", index=1)

  # writing trees to files
  println("Use 'write_yaml(tree, filename)' to write the edited tree to a file.")
  pj.write_yaml(tree, expand_file)
  println("Wrote tree to 'expand.pals.yaml'\n\n\n")

  println("========== Printing Final Modified Tree ==========")
  println(pj.to_yaml_string(tree))
end

main()