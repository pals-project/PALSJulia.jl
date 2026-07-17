using Test
using PALSJulia
using PALSJulia: parse_and_expand_pals, node_correspondence, parse_string

# A self-contained lattice: `a_const` sits outside the expanded lattice (so it
# is left over rather than expanded), while `repeat: 3` exercises the
# one-to-many correspondence produced by expansion.
const CORR_LATTICE = """
PALS:
  facility:
    - constants:
        a_const: 0.3 * r_electron
    - d1:
        kind: Drift
        length: 2.0
    - cell:
        kind: BeamLine
        line:
          - d1
    - main_line:
        kind: BeamLine
        line:
          - cell:
              repeat: 3
    - lat1:
        kind: Lattice
        branches:
          - main_line
    - use: "lat1"
"""

@testset "Node Correspondence" begin
  mktempdir() do dir
    path = joinpath(dir, "corr.pals.yaml")
    write(path, CORR_LATTICE)

    lat  = parse_and_expand_pals(path)
    corr = node_correspondence(lat)

    @testset "returns a Dict keyed by node" begin
      @test corr isa Dict
      @test !isempty(corr)
      # The combined, expanded and leftover roots are keys.
      @test haskey(corr, lat.combined)
      @test haskey(corr, lat.expanded)
      @test haskey(corr, lat.leftover)
    end

    # a_const is not part of the lattice and nothing in it refers to a_const, so
    # expansion leaves it behind: one node in original, combined and leftover,
    # and none in expanded.
    a_const = lat.combined["PALS"]["facility"][1]["constants"]["a_const"]
    entry = corr[a_const]

    @testset "a node outside the lattice maps into leftover, not expanded" begin
      @test length(entry.original) == 1
      @test length(entry.combined) == 1
      @test length(entry.leftover) == 1
      @test isempty(entry.expanded)
      @test String(entry.original[1]) == "0.3 * r_electron"
      @test String(entry.combined[1]) == "0.3 * r_electron"
      # The leftover copy has its expression evaluated to a number, while the
      # original/combined copies keep the original expression text.
      @test Float64(entry.leftover[1]) == evaluate_pals_expression("0.3 * r_electron")
      # The queried node appears in its own tree's vector.
      @test entry.combined[1] == a_const
    end

    @testset "lookup is consistent from any tree" begin
      # Reaching the class from the original or leftover node gives the same set.
      @test corr[entry.original[1]] == entry
      @test corr[entry.leftover[1]] == entry
    end

    @testset "repeat gives one-to-many correspondence" begin
      # The single `d1` scalar in cell's line is unrolled 3x inside the expanded
      # lattice, so it corresponds to several expanded nodes but one combined.
      cell_d1 = lat.combined["PALS"]["facility"][3]["cell"]["line"][1]
      c = corr[cell_d1]
      @test length(c.combined) == 1
      @test length(c.expanded) >= 3
      # Every expanded copy resolves back to this same class.
      @test all(corr[n] == c for n in c.expanded)
      # The definition it was expanded from is still standing in leftover, and
      # belongs to the same class.
      @test length(c.leftover) == 1
      @test corr[c.leftover[1]] == c
    end

    @testset "a definition used by the lattice reaches both trees" begin
      # main_line is named by lat1's branches, so expansion inlines a copy of its
      # definition into the lattice while the definition itself stays in
      # leftover. The combined node ties the two sides together. `line` is the
      # node to follow, not `kind`: inlining main_line made it a branch, and a
      # branch has no kind, so no expanded node answers to main_line's.
      ml = lat.combined["PALS"]["facility"][4]["main_line"]
      @test isempty(corr[ml["kind"]].expanded)

      c = corr[ml["line"]]
      @test length(c.combined) == 1
      @test length(c.leftover) == 1
      @test length(c.expanded) == 1
      # The two copies are the same node of the same definition, but only the
      # expanded one has been expanded: `cell: repeat: 3` is unrolled to 3
      # entries there, while the definition in leftover still holds the 1 entry
      # it was written with.
      @test length(c.leftover[1]) == 1
      @test length(c.expanded[1]) == 3
      # Both copies resolve back to the same class.
      @test corr[c.expanded[1]] == c
      @test corr[c.leftover[1]] == c
    end

    @testset "unmapped nodes are absent from the Dict" begin
      # A freshly built, unrelated tree shares no nodes with the correspondence.
      other = parse_string("stray: node")
      @test !haskey(corr, other)
    end
  end
end
