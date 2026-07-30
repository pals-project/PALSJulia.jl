using Test
using PALSJulia
using PALSJulia: parse_and_expand_pals

# One element carrying enough reference data for the bookkeeper to run, so the
# derived parameters it computes are there to tell the two expanded views apart.
# `Kn1: 2 * 0.6` doubles as the marker for the pre-expansion views, which keep
# the expression text.
const VIEWS_LATTICE = """
PALS:
  facility:
    - ring:
        kind: Lattice
        branches:
          - main:
              kind: BeamLine
              line:
                - q1:
                    kind: Quadrupole
                    length: 0.5
                    ReferenceP:
                      species_ref: electron
                      pc_ref: 1e9
                    MagneticMultipoleP:
                      Kn1: 2 * 0.6
    - use: ring
"""

# Each handle of `struct lattices` is read by position, so a field added to the
# C struct and missed here would silently hand back the neighbouring tree. These
# check every view is the one it claims to be.
@testset "Lattice Views" begin
  mktempdir() do dir
    path = joinpath(dir, "views.pals.yaml")
    write(path, VIEWS_LATTICE)
    lat = parse_and_expand_pals(path; problems = :none)

    q1(view) = view["ring"]["branches"][1]["main"]["line"][1]["q1"]

    @testset "the five views are five distinct trees" begin
      trees = [v.tree for v in (lat.original, lat.combined, lat.expanded,
                                lat.full_expanded, lat.adjunct)]
      @test length(unique(objectid.(trees))) == 5
      @test isempty(lat.problems)
    end

    @testset "original and combined keep the pre-expansion text" begin
      # original is keyed by the path of each file read, combined by the PALS root.
      @test collect(keys(lat.original)) == [path]
      @test haskey(lat.combined, "PALS")
      for root in (lat.original[path], lat.combined)
        q1_raw = root["PALS"]["facility"][1]["ring"]["branches"][1]["main"]["line"][1]["q1"]
        @test String(q1_raw["MagneticMultipoleP"]["Kn1"]) == "2 * 0.6"
      end
    end

    @testset "adjunct keeps the facility scaffolding" begin
      @test haskey(lat.adjunct, "PALS")
      @test !haskey(lat.adjunct, "ring")
    end

    @testset "both expanded views are rooted at the lattice" begin
      for view in (lat.expanded, lat.full_expanded)
        @test haskey(view, "ring")
        @test !haskey(view, "PALS")
      end
    end

    @testset "what the author wrote is the same in both" begin
      for view in (lat.expanded, lat.full_expanded)
        @test Float64(q1(view)["length"]) == 0.5
        # Evaluated in both, so a value shared by the two views agrees.
        @test Float64(q1(view)["MagneticMultipoleP"]["Kn1"]) ≈ 1.2
      end
    end

    @testset "only full_expanded carries the computed parameters" begin
      full, exp = q1(lat.full_expanded), q1(lat.expanded)
      # Derived member of a parameter family the element uses.
      @test haskey(full["MagneticMultipoleP"], "Kn1L")
      @test !haskey(exp["MagneticMultipoleP"], "Kn1L")
      # Placement, and a group the author never wrote.
      @test haskey(full, "s_position")
      @test !haskey(exp, "s_position")
      @test haskey(full, "FloorP")
      @test !haskey(exp, "FloorP")
      # The branch_end Placeholder capping the branch is pruned as well.
      @test length(lat.full_expanded["ring"]["branches"][1]["main"]["line"]) == 2
      @test length(lat.expanded["ring"]["branches"][1]["main"]["line"]) == 1
    end
  end
end
