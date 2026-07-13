# Produces a file "PALSJulia/lattice_files/bta.pals_out.bmad"

using PALSJulia
using PALSJulia: parse_file

pals_dir = joinpath(@__DIR__, "..")
ex_file     = joinpath(pals_dir, "lattice_files", "bta.pals.yaml")
out_file    = joinpath(pals_dir, "lattice_files", "bta.pals_out.bmad")
write_bmad_file(pals_to_bmad(parse_file(ex_file)), out_file)
