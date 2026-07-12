file_name    = joinpath(@__DIR__, "..", "lattice_files", "ex.pals.yaml")
lattice_dir  = joinpath(@__DIR__, "..", "lattice_files")
lattice_name = ""

# ARGS[1] is the first user-supplied argument (no script name in Julia).
if length(ARGS) >= 1 && ARGS[1] != "-lat"
  file_name = ARGS[1]
end

for i in 1:length(ARGS)
  if ARGS[i] == "-lat" && i < length(ARGS)
    lattice_name = ARGS[i + 1]
  end
end

# cd into the lattice directory so that relative include paths inside the
# YAML files resolve correctly when the C library opens them.
lat = cd(lattice_dir) do
  get_lattices(file_name, lattice_name)
end

println("Printing original lattice information:")
println(to_yaml_string(lat.original))
println("\n", "-"^50)

println("Printing included lattice information:")
println(to_yaml_string(lat.included))
println("\n", "-"^50)

println("Printing expanded lattice information:")
println(to_yaml_string(lat.expanded))
