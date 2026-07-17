# Example that reads in a PALS file and prints the resulting tree created in memory.

using PALSJulia
import PALSJulia as pj

file_name    = joinpath(@__DIR__, "..", "lattice_files", "ex.pals.yaml")
lattice_dir  = joinpath(@__DIR__, "..", "lattice_files")
root_lattice = ""

lat = parse_and_expand_pals(file_name, root_lattice)

println("Printing original lattice information:")
println(pj.to_yaml_string(lat.original))
println("\n", "-"^50)

println("Printing combined lattice information:")
println(pj.to_yaml_string(lat.combined))
println("\n", "-"^50)

println("Printing expanded lattice information:")
println(pj.to_yaml_string(lat.expanded))
println("\n", "-"^50)

println("Printing what expansion left over:")
println(pj.to_yaml_string(lat.leftover))

