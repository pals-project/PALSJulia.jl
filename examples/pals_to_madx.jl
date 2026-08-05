# Produces a file "PALSParserJ/lattice_files/bta.pals_out.madx"

using PALSParserJ
using PALSParserJ: parse_file

pals_dir = joinpath(@__DIR__, "..")
ex_file     = joinpath(pals_dir, "lattice_files", "bta.pals.yaml")
out_file    = joinpath(pals_dir, "lattice_files", "bta.pals_out.madx")
write_madx_file(pals_to_madx(parse_file(ex_file)), out_file)
