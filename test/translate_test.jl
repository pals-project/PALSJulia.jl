using Test
using PALSJulia   # pals_to_bmad / write_bmad_file / pals_to_scibmad / write_scibmad_file are exported
using PALSJulia: parse_file   # not exported by default; the translators now take a parsed tree

# A small but structurally complete PALS lattice.  It exercises every branch of
# the translator dispatch: a BeginningEle (reference / particle-start settings),
# a couple of ordinary elements, a BeamLine, and a Lattice with one branch.
# The first `line` member is a map here, spelling the beginning element out;
# _CONTROLLER_FIXTURE below names it instead, which is the other form.
const _TRANSLATE_FIXTURE = """
  PALS:
    facility:
      - beg:
          kind: BeginningEle
          length: 0
          ReferenceP:
            species_ref: electron
            pc_ref: 3E6
          TwissP:
            beta_a: 10
            alpha_a: 0.5
            cmat11: 0.1
            deta_x_ds: 0.2
          ParticleP:
            x: 1
            px: 4
            spin_x: 1
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

# A lattice built around the two `Controller` kinds.  It also names its beginning
# element in the `line` rather than spelling it out, gives its branch as a map, and
# gives q1 an aperture with a shape but no limits — all forms the translators have
# to accept.
const _CONTROLLER_FIXTURE = """
  PALS:
    facility:
      - beg:
          kind: BeginningEle
          ReferenceP:
            species_ref: electron
            pc_ref: 3E6
      - q1:
          kind: Quadrupole
          length: 0.5
          MagneticMultipoleP:
            Kn1: 0.25
          ApertureP:
            shape: RECTANGULAR
            location: EXIT_END
      - s1:
          kind: Sextupole
          length: 0.2
          MagneticMultipoleP:
            Ks2L: 1.5
      - ring:
          kind: BeamLine
          line:
            - beg
            - q1
            - s1
      - lat:
          kind: Lattice
          branches:
            - ring:
                periodic: false
      - knob:
          kind: Controller
          control_type: ABSOLUTE
          variables:
            k: 0.3
          controls:
            - parameter: q1>MagneticMultipoleP.Kn1
              expression: 2*k
      - bump:
          kind: Controller
          control_type: RELATIVE
          variables:
            dk: 0.0
          controls:
            - parameter: s1>MagneticMultipoleP.Ks2L
              expression: dk
  """

# `_CONTROLLER_FIXTURE` with its `knob` control aimed at every quadrupole at once.
const _PATTERN_FIXTURE =
    replace(_CONTROLLER_FIXTURE, "parameter: q1>MagneticMultipoleP.Kn1" =>
                                 "parameter: q.*>MagneticMultipoleP.Kn1")

# Writes `text` to a file in `dir` and returns the parsed tree.
_parsed(dir, text) = (path = joinpath(dir, "fixture.pals.yaml");
                      write(path, text); parse_file(path))

@testset "PALS translation" begin

  @testset "pals_to_bmad / write_bmad_file writes a Bmad lattice file" begin
    mktempdir() do dir
      in_path = joinpath(dir, "fixture.pals.yaml")
      write(in_path, _TRANSLATE_FIXTURE)

      bmad = pals_to_bmad(parse_file(in_path))
      out_path = joinpath(dir, "fixture.pals_out.bmad")
      write_bmad_file(bmad, out_path)

      @test isfile(out_path)
      out = read(out_path, String)

      # BeginningEle → global parameter / beginning / particle_start settings.
      @test occursin("parameter[particle] = electron", out)
      @test occursin("parameter[p0c] = 3E6", out)
      @test occursin("particle_start[x] = 1", out)
      @test occursin("particle_start[px] = 4", out)
      @test occursin("particle_start[spin_x] = 1", out)

      # TwissP → the beginning element. Bmad and PALS agree on these names except for the
      # coupling matrix, where Bmad has an underscore.
      @test occursin("beginning[beta_a] = 10", out)
      @test occursin("beginning[alpha_a] = 0.5", out)
      @test occursin("beginning[cmat_11] = 0.1", out)
      @test occursin("beginning[deta_x_ds] = 0.2", out)

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

      scibmad = pals_to_scibmad(parse_file(in_path))
      out_path = joinpath(dir, "fixture.pals_out.jl")
      write_scibmad_file(scibmad, out_path)

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

  @testset "a Controller becomes a Bmad overlay or group" begin
    mktempdir() do dir
      bmad = pals_to_bmad(_parsed(dir, _CONTROLLER_FIXTURE))
      out_path = joinpath(dir, "fixture.pals_out.bmad")
      write_bmad_file(bmad, out_path)
      out = read(out_path, String)

      # ABSOLUTE sets the parameter, so it is an overlay.  The element translation turns
      # `Kn1` into the integrated `B1`, so the expression picks up q1's half-metre length.
      @test occursin("knob: overlay = {q1[B1]: 0.5*(2*k)}, var = {k}, k = 0.3", out)

      # RELATIVE adds to the parameter, so it is a group.  `Ks2L` is already integrated --
      # no length -- but is skew and second order, hence A2 and the 1/2! of the convention.
      @test occursin("bump: group = {s1[A2]: 0.5*(dk)}, var = {dk}, dk = 0.0", out)

      # The rest of the lattice still comes through.
      @test occursin("ring: line = (q1, s1)", out)
      @test occursin("use, ring", out)
    end
  end

  @testset "a Controller becomes a SciBmad Controller" begin
    mktempdir() do dir
      scibmad = pals_to_scibmad(_parsed(dir, _CONTROLLER_FIXTURE))
      out_path = joinpath(dir, "fixture.pals_out.jl")
      write_scibmad_file(scibmad, out_path)
      out = read(out_path, String)

      # SciBmad keeps the PALS parameter names, so only the group prefix is dropped and
      # nothing needs rescaling.  Every control takes all of the controller's variables.
      @test occursin("knob = Controller(", out)
      @test occursin("(q1, :Kn1) => (ele; k) -> 2*k", out)
      @test occursin("vars = (; k = 0.3)", out)

      # RELATIVE adds to the value the element already carries.
      @test occursin("bump = Controller(", out)
      @test occursin("(s1, :Ks2L) => (ele; dk) -> ele.Ks2L + (dk)", out)

      # An aperture with a shape but no limits gives a shape and no limits.
      @test occursin("aperture_shape = ApertureShape.Rectangular", out)
      @test !occursin("x1_limit", out)

      # The line names its beginning element; its reference parameters still reach the
      # beamline, and the branch given as a map still reaches the lattice list.
      @test occursin("species_ref = electron", out)
      @test occursin("lat = [ring,]", out)
    end
  end

  @testset "a control target neither translator can express is reported" begin
    mktempdir() do dir
      yaml = _parsed(dir, _PATTERN_FIXTURE)
      @test_throws "selects slaves by pattern" pals_to_bmad(yaml)
      @test_throws "selects slaves by pattern" pals_to_scibmad(yaml)
    end
  end

end
