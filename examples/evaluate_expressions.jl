# Example: evaluating the mathematical expressions in a PALS lattice.
#
# When parse_and_expand_pals builds the `expanded` view it evaluates every
# expression to a number, drawing on built-in physical constants, math and
# particle-data functions, and any constants/variables the lattice defines. The
# `original` and `combined` views keep the expression text as written.
# evaluate_pals_expression evaluates a single expression string on its own.

using PALSJulia
import PALSJulia as pj

ex_file = joinpath(@__DIR__, "..", "lattice_files", "ex.pals.yaml")

lat = pj.parse_and_expand_pals(ex_file)

# ── combined keeps the source text; expanded holds the evaluated number ───────
consts_c = lat.combined["PALS"]["facility"][1]["constants"]
consts_e = lat.expanded["PALS"]["facility"][1]["constants"]
vars_e   = lat.expanded["PALS"]["facility"][2]["variables"]

println("a_const  as written : ", String(consts_c["a_const"]))   # 0.3 * r_electron
println("a_const  evaluated  : ", String(consts_e["a_const"]))   # a number
# a_var references the constant a_const defined above it.
println("a_var    evaluated  : ", String(vars_e["a_var"]), "  (= a_const^2)\n")

# ── an element parameter written as an expression is evaluated too ────────────
q1a_length = pj.match_names(lat.expanded, "Q1a>length")   # length: 1.03 * pi / c_light
if !isempty(q1a_length)
  println("Q1a length evaluated: ", String(q1a_length[1]), "  (= 1.03 * pi / c_light)\n")
end

# ── evaluating a single expression on its own ────────────────────────────────
# Built-in constants and math functions:
println("3.75e7 / c_light^2   = ", pj.evaluate_pals_expression("3.75e7 / c_light^2"))
# Particle-data functions take a *quoted* species name:
println("mass_of(\"electron\") = ", pj.evaluate_pals_expression("mass_of(\"electron\")"))
# A leading expr(...) wrapper is accepted:
println("expr(2 * pi)         = ", pj.evaluate_pals_expression("expr(2 * pi)"))

# Non-evaluable strings throw ArgumentError — e.g. an unquoted species name, or
# a deferred random_gauss(). Guard with a try/catch if the input is untrusted:
try
  pj.evaluate_pals_expression("mass_of(electron)")   # unquoted → error
catch err
  println("\nunquoted species name is rejected: ", err)
end
