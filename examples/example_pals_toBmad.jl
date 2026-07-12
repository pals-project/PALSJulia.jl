if abspath(PROGRAM_FILE) == @__FILE__
    pals_dir = joinpath(@__DIR__, "..")
    ex_file     = joinpath(pals_dir, "lattice_files", "bta.pals.yaml")

    include(joinpath(pals_dir, "src", "toBmad.jl"))

    # Produces a file "PALSJulia/lattice_files/bta.pals_out.bmad"
    main(ex_file)
end