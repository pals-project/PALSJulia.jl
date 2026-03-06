import Pkg
Pkg.activate(joinpath(@__DIR__, ".."))
import pals_julia as pj

function main()
    # Default values
    file_name = joinpath(@__DIR__, "..", "lattice_files", "ex.pals.yaml")    
    lattice_dir = joinpath(@__DIR__, "..", "lattice_files")
    lattice_name = ""
    

    # In Julia, ARGS only contains the arguments, not the script name.
    # So ARGS[1] is the first actual argument provided by the user.
    if length(ARGS) >= 1 && ARGS[1] != "-lat"
        file_name = ARGS[1]
    end

    # Parse the -lat flag
    for i in 1:length(ARGS)
        if ARGS[i] == "-lat" && i < length(ARGS)
            lattice_name = ARGS[i+1]
        end
    end
    
    # Fetch the lattices (using the variable, not the hardcoded string!)
    lat = cd(lattice_dir) do
        # Because Julia is now "standing" in the lattice_files folder,
        # when C++ looks for "include.pals.yaml", it will find it instantly!
        pj.get_lattices(file_name, lattice_name)
    end

    println("Printing original lattice information: ")
    println(pj.to_yaml_string(lat.original))
    println("\n")

    # Separating line
    println("-" ^ 50)

    println("Printing included lattice information: ")
    println(pj.to_yaml_string(lat.included))
    println("\n")

    println("-" ^ 50)

    println("Printing expanded lattice information: ")
    println(pj.to_yaml_string(lat.expanded))
end

# Run the main function
main()