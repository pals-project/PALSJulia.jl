using Test
using PALSJulia   # pals_to_bmad / write_bmad_file / pals_to_scibmad / write_scibmad_file are exported

# A small but structurally complete PALS lattice.  It exercises every branch of
# the translator dispatch: a BeginningEle (reference / particle-start settings),
# a couple of ordinary elements, a BeamLine, and a Lattice with one branch.
# The first `line` member is a map on purpose — both translators skip line[1]
# and toSciBmad reads its key, so a scalar there would break _make_beamline_str.
const _TRANSLATE_FIXTURE = """
  PALS:
    facility:
      - beg:
          kind: BeginningEle
          length: 0
          ReferenceP:
            species_ref: electron
            pc_ref: 3E6
          ParticleP:
            x: 1
            px: 4
      - d1:
          kind: Drift
          length: 100
      - q1:
          kind: Quadrupole
          length: 0.5
      - ring:
          kind: BeamLine
          line:
            - beg:
                kind: BeginningEle
                ReferenceP:
                  species_ref: electron
                  pc_ref: 3E6
            - d1
            - q1
      - lat:
          kind: Lattice
          branches:
            - ring
  """

@testset "PALS translation" begin

  @testset "pals_to_bmad / write_bmad_file writes a Bmad lattice file" begin
    mktempdir() do dir
      in_path = joinpath(dir, "fixture.pals.yaml")
      write(in_path, _TRANSLATE_FIXTURE)

      yaml = pals_to_bmad(in_path)
      out_path = joinpath(dir, "fixture.pals_out.bmad")
      write_bmad_file(yaml, out_path)

      @test isfile(out_path)
      out = read(out_path, String)

      # BeginningEle → global parameter / particle_start settings.
      @test occursin("parameter[particle] = electron", out)
      @test occursin("parameter[p0c] = 3E6", out)
      @test occursin("particle_start[x] = 1", out)
      @test occursin("particle_start[px] = 4", out)

      # Ordinary element definitions.
      @test occursin("d1: Drift", out)
      @test occursin("L = 100", out)
      @test occursin("q1: Quadrupole", out)

      # BeamLine definition (line[1] is dropped by design, leaving d1, q1).
      @test occursin("ring: line = (d1, q1)", out)

      # Branch structure.
      @test occursin("parameter[geometry] = open", out)
      @test occursin("use, ring", out)
    end
  end

  @testset "pals_to_scibmad / write_scibmad_file writes a SciBmad lattice file" begin
    mktempdir() do dir
      in_path = joinpath(dir, "fixture.pals.yaml")
      write(in_path, _TRANSLATE_FIXTURE)

      yaml = pals_to_scibmad(in_path)
      out_path = joinpath(dir, "fixture.pals_out.jl")
      write_scibmad_file(yaml, out_path)

      @test isfile(out_path)
      out = read(out_path, String)

      # @elements block with the ordinary elements.
      @test occursin("@elements begin", out)
      @test occursin("d1 = LineElement(", out)
      @test occursin("kind = Drift", out)
      @test occursin("L = 100", out)
      @test occursin("q1 = LineElement(", out)

      # BeginningEle → particle coordinates and the phase-space vector.
      @test occursin("x = 1", out)
      @test occursin("v = [ x px y py z pz ]", out)

      # Beamline and lattice list.
      @test occursin("ring = Beamline([", out)
      @test occursin("lat = [ring,]", out)
    end
  end

end
