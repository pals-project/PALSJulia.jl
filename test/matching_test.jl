using Test
using PALSJulia
using PALSJulia: match_names, parse_string, node_key

# A self-contained two-lattice lattice: constants/variables at the top, elements
# with ungrouped (`length`) and grouped (`BendP.e1`) parameters, a sub-line
# (sub/S1), and a repeated element name (B1a in both lattices) to exercise `>>>`.
const MATCH_LATTICE = """
PALS:
  facility:
    - constants:
        - a_const: 0.3 * r_electron
        - a_two: 5
    - my_var:
        kind: variable
        value: 37
    - lat1:
        kind: Lattice
        branches:
          - main:
              kind: BeamLine
              line:
                - B1a:
                    kind: Bend
                    length: 1.2
                    BendP:
                      e1: 0.1
                      g_ref: 0.02
                - B1b:
                    kind: Bend
                    length: 1.5
                    BendP:
                      e1: 0.3
                - Q1:
                    kind: Quadrupole
                    length: 0.5
                - sub:
                    kind: BeamLine
                    line:
                      - S1:
                          kind: Sextupole
                          length: 0.2
    - lat2:
        kind: Lattice
        branches:
          - other:
              kind: BeamLine
              line:
                - B1a:
                    kind: Bend
                    length: 9.9
"""

@testset "Name Matching" begin
  root = parse_string(MATCH_LATTICE)

  @testset "constants and variables (bare name)" begin
    m = match_names(root, "a_const")
    @test length(m) == 1
    @test node_key(m[1]) == "a_const"
    @test String(m[1]) == "0.3 * r_electron"

    m = match_names(root, "a_.*")
    @test Set(node_key.(m)) == Set(["a_const", "a_two"])

    m = match_names(root, "my_var")             # full form -> named map node
    @test length(m) == 1
    @test node_key(m[1]) == "my_var"
    @test is_map(m[1])

    @test isempty(match_names(root, "a"))       # anchored whole-name match
  end

  @testset "bare name matches the elements themselves" begin
    m = match_names(root, "B1a")                # in both lattices
    @test length(m) == 2
    @test all(node_key(n) == "B1a" && is_map(n) for n in m)
  end

  @testset "element parameters" begin
    m = match_names(root, "B1.*>BendP.e1")      # lat1's B1a, B1b
    @test Set(String.(m)) == Set(["0.1", "0.3"])

    m = match_names(root, "B1a>length")         # both lattices
    @test Set(String.(m)) == Set(["1.2", "9.9"])

    @test length(match_names(root, ">length")) == 5   # every element

    m = match_names(root, ">BendP.g_ref")
    @test length(m) == 1
    @test node_key(m[1]) == "g_ref"

    m = match_names(root, "B1a>BendP")          # drop parameter -> group node
    @test length(m) == 1
    @test node_key(m[1]) == "BendP"
    @test is_map(m[1])
  end

  @testset "`::` kind restriction" begin
    m = match_names(root, "Quadrupole::.*>length")
    @test length(m) == 1
    @test String(m[1]) == "0.5"

    @test length(match_names(root, "Bend::B1a>length")) == 2
    @test isempty(match_names(root, "Sextupole::B1a>length"))
  end

  @testset "`>>` branch filter, sub-lines included" begin
    @test length(match_names(root, "main>>B1.*>length")) == 2

    m = match_names(root, "main>>S1>length")    # S1 is in sub-line of main
    @test length(m) == 1
    @test String(m[1]) == "0.2"

    @test isempty(match_names(root, "nobranch>>B1.*>length"))
  end

  @testset "`>>>` lattice qualifier" begin
    m = match_names(root, "lat1>>>B1a>length")
    @test length(m) == 1
    @test String(m[1]) == "1.2"

    m = match_names(root, "lat2>>>B1a>length")
    @test length(m) == 1
    @test String(m[1]) == "9.9"
  end

  @testset "non-matches and bad patterns" begin
    @test isempty(match_names(root, "nosuch>foo"))
    @test isempty(match_names(root, "B1a>BendP.nope"))
    @test isempty(match_names(root, "(unclosed"))
  end

  @testset "returned nodes belong to the searched tree" begin
    m = match_names(root, "lat1>>>B1a>length")
    @test m[1].tree === root.tree
  end
end
