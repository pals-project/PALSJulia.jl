using Test
using PALSJulia
using PALSJulia: parameter_value, parse_and_expand_pals

# A single expandable lattice. Its branch line inline-defines the elements (so
# they are realised in the expanded tree), with a plain-number parameter, an
# expression parameter (to show it comes back evaluated, i.e. from `expanded`,
# not from the raw views), and a non-numeric one. Two quads with different Bn1
# exercise the conflict case. Facility-level constants and a variable live in the
# leftover tree.
const PARAM_LATTICE = """
PALS:
  facility:
    - constants:
        - a_two: 5
        - a_expr: 0.3 * 5
    - my_var:
        kind: variable
        value: 37
    - ring:
        kind: Lattice
        branches:
          - main:
              kind: BeamLine
              line:
                - q1:
                    kind: Quadrupole
                    length: 0.5
                    MagneticMultipoleP:
                      Bn1: 2 * 0.6
                - q2:
                    kind: Quadrupole
                    MagneticMultipoleP:
                      Bn1: -1.0
                - f1:
                    kind: Foil
                    ReferenceP:
                      species_ref: "#3He"
    - use: ring
"""

@testset "Parameter Values" begin
  mktempdir() do dir
    path = joinpath(dir, "params.pals.yaml")
    write(path, PARAM_LATTICE)
    lat = parse_and_expand_pals(path; problems = :none)
    pv(s) = parameter_value(lat, s)

    @testset "element parameters come from the expanded lattice" begin
      @test pv("q1>length") == 0.5
      # 2 * 0.6 comes back evaluated (1.2), proving the value is read from
      # `expanded` and not from the raw `original`/`combined` views.
      @test pv("q1>MagneticMultipoleP.Bn1") == 1.2
      @test pv("q2>MagneticMultipoleP.Bn1") == -1.0
    end

    @testset "non-numeric values stay strings" begin
      @test pv("f1>ReferenceP.species_ref") == "#3He"
      @test pv("q1>kind") == "Quadrupole"
    end

    @testset "unset parameters return the default (0 for now)" begin
      @test pv("q1>BendP.g") === 0.0            # element found, parameter absent
      @test pv("q1>not_a_param") === 0.0        # no schema: unknown == unset -> 0
    end

    @testset "constants and variables fall through to leftover" begin
      @test pv("a_two") == 5.0                  # compact-form constant
      @test pv("a_expr") == 1.5                 # evaluated in leftover during expansion
      @test pv("my_var") == 37.0                # full-form variable
    end

    @testset "unidentifiable lookups return missing" begin
      @test pv("nosuch>length") === missing     # in neither view
      @test pv("q1") === missing                # a bare element is not a value
      @test pv("q1>MagneticMultipoleP") === missing  # a group, not a single value
      @test pv("(unclosed>length") === missing  # malformed pattern
      @test pv("nosuch_const") === missing
    end

    @testset "agreeing matches collapse, conflicts are missing" begin
      @test pv("q.>MagneticMultipoleP.Bn1") === missing  # 1.2 vs -1.0 conflict
      @test pv("q.>kind") == "Quadrupole"                # both quads agree
    end
  end
end
