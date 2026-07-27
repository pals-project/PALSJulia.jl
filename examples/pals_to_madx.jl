# Produces a file "PALSJulia/lattice_files/bta.pals_out.madx"

using PALSJulia
using PALSJulia: parse_file

pals_dir = joinpath(@__DIR__, "..")
ex_file     = joinpath(pals_dir, "lattice_files", "bta.pals.yaml")
out_file    = joinpath(pals_dir, "lattice_files", "bta.pals_out.madx")
write_madx_file(pals_to_madx(parse_file(ex_file)), out_file)
