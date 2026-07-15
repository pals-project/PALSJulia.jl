using Test
using PALSJulia
using PALSJulia: parse_and_expand_pals, node_correspondence, parse_string

# A self-contained lattice: `a_const` sits outside the expanded lattice (so it
# is identical across all three trees), while `repeat: 3` exercises the
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
      # The combined and expanded roots are keys.
      @test haskey(corr, lat.combined)
      @test haskey(corr, lat.expanded)
    end

    # a_const is untouched by expansion: one node in each of the three trees.
    a_const = lat.combined["PALS"]["facility"][1]["constants"]["a_const"]
    entry = corr[a_const]

    @testset "one-to-one node maps across all three trees" begin
      @test length(entry.original) == 1
      @test length(entry.combined) == 1
      @test length(entry.expanded) == 1
      @test String(entry.original[1]) == "0.3 * r_electron"
      @test String(entry.combined[1]) == "0.3 * r_electron"
      @test String(entry.expanded[1]) == "0.3 * r_electron"
      # The queried node appears in its own tree's vector.
      @test entry.combined[1] == a_const
    end

    @testset "lookup is consistent from any tree" begin
      # Reaching the class from the original or expanded node gives the same set.
      @test corr[entry.original[1]] == entry
      @test corr[entry.expanded[1]] == entry
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
    end

    @testset "unmapped nodes are absent from the Dict" begin
      # A freshly built, unrelated tree shares no nodes with the correspondence.
      other = parse_string("stray: node")
      @test !haskey(corr, other)
    end
  end
end
