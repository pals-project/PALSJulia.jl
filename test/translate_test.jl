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
          ApertureP:
            shape: RECTANGULAR
            x_min: -0.03
            x_max: 0.05
            y_min: -0.01
            y_max: 0.02
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
# to accept.  s1's aperture does set limits, so the two can be told apart.  m1 carries
# nothing but multipoles, which Bmad handles its own way.
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
          ApertureP:
            shape: ELLIPTICAL
            location: BOTH_ENDS
            x_width: 0.25
            x_center: 0.0625
            y_width: 0.5
            y_center: 0.125
      - m1:
          kind: Multipole
          MagneticMultipoleP:
            Kn3L: 0.7
      - ring:
          kind: BeamLine
          line:
            - beg
            - q1
            - s1
            - m1
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

# One quadrupole for each form a PALS multipole of the element's own order can take, a tilted
# sextupole, and an element that is nothing but multipoles.  The controller drives one parameter
# of each, so the elements and the controls can be checked against each other.
const _STRENGTH_FIXTURE = """
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
            Kn3: 0.4
      - q2:
          kind: Quadrupole
          length: 2
          MagneticMultipoleP:
            Kn1L: 0.6
      - q3:
          kind: Quadrupole
          length: 0.5
          MagneticMultipoleP:
            Bn1: 3.0
      - q4:
          kind: Quadrupole
          length: 0.5
          MagneticMultipoleP:
            Ks1: 0.8
      - s2:
          kind: Sextupole
          length: 1
          MagneticMultipoleP:
            Kn2: 1.0
            tilt2: 0.1
      - m1:
          kind: Multipole
          MagneticMultipoleP:
            Kn3L: 0.7
      - kk:
          kind: Controller
          variables:
            a: 1.0
          controls:
            - parameter: q1>MagneticMultipoleP.Kn1
              expression: a
            - parameter: q2>MagneticMultipoleP.Kn1L
              expression: a
            - parameter: q3>MagneticMultipoleP.Bn1
              expression: a
            - parameter: q4>MagneticMultipoleP.Ks1
              expression: a
            - parameter: q1>MagneticMultipoleP.Kn3
              expression: a
      - ring:
          kind: BeamLine
          line:
            - beg
            - q1
            - q2
            - q3
            - q4
            - s2
            - m1
      - lat:
          kind: Lattice
          branches:
            - ring
  """

# A bend for each form its order-0 field can take: a plain one, one whose field is the reference
# bend itself, an integrated one measured against a `radius_ref`, and an unnormalized one.  The
# controllers drive b1's field absolutely and b2's relatively.
const _BEND_FIXTURE = """
  PALS:
    facility:
      - beg:
          kind: BeginningEle
          ReferenceP:
            species_ref: electron
            pc_ref: 3E6
      - b1:
          kind: Bend
          length: 1
          BendP:
            g_ref: 0.5
          MagneticMultipoleP:
            Kn0: 0.75
      - b2:
          kind: Bend
          length: 1
          BendP:
            g_ref: 0.5
          MagneticMultipoleP:
            Kn0: 0.5
            Kn1: 0.2
      - b3:
          kind: Bend
          length: 2
          BendP:
            radius_ref: 4
          MagneticMultipoleP:
            Kn0L: 1.5
      - b4:
          kind: Bend
          length: 1
          BendP:
            Bn0_ref: 2.0
          MagneticMultipoleP:
            Bn0: 3.0
      - knob:
          kind: Controller
          control_type: ABSOLUTE
          variables:
            kk0: 0.6
          controls:
            - parameter: b1>MagneticMultipoleP.Kn0
              expression: kk0
      - bump:
          kind: Controller
          control_type: RELATIVE
          variables:
            dkk0: 0.0
          controls:
            - parameter: b2>MagneticMultipoleP.Kn0
              expression: dkk0
      - ring:
          kind: BeamLine
          line:
            - beg
            - b1
            - b2
            - b3
            - b4
      - lat:
          kind: Lattice
          branches:
            - ring
  """

# `_BEND_FIXTURE` with b1's reference bend given as a field, which its normalized `Kn0` has no
# way of being measured against.
const _BEND_MISMATCH_FIXTURE = replace(_BEND_FIXTURE, "g_ref: 0.5" => "Bn0_ref: 0.5", count = 1)

# The MetaP components Bmad keeps, one it has no place for, one that is a structure rather than
# a string, and one whose text contains the quote character it would normally be wrapped in.
const _META_FIXTURE = """
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
          MetaP:
            alias: q_one
            label: AGSBPM
            description: A quadrupole
            ID: 0137-85
            history:
              - 2022-04-01: Fixed water leak to vacuum.
      - q2:
          kind: Quadrupole
          length: 0.5
          MetaP:
            label: 'has a " double quote'
      - ring:
          kind: BeamLine
          line:
            - beg
            - q1
            - q2
      - lat:
          kind: Lattice
          branches:
            - ring
  """

# Constants and variables in both the forms the standard allows -- the compact `constants:` /
# `variables:` lists and the full `kind: constant` / `kind: variable` definitions -- defined
# both directly under `PALS` and in the facility, one of them written with no value, and an
# element whose length is given as one of them.
const _CONSTANT_FIXTURE = """
  PALS:
    constants:
      - c_top: 1.5
    facility:
      - constants:
          - c_one: 0.3
          - c_two: 2 * c_one
      - variables:
          - v_one: 0.5
          - v_two:
      - m_e:
          kind: constant
          value: mass_of("electron")
      - my_var:
          kind: variable
          value: 37
      - beg:
          kind: BeginningEle
          ReferenceP:
            species_ref: electron
            pc_ref: 3E6
      - q1:
          kind: Quadrupole
          length: c_one
      - ring:
          kind: BeamLine
          line:
            - beg
            - q1
      - lat:
          kind: Lattice
          branches:
            - ring
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

      # No element here has multipoles, so none of them needs the scaling turned off.
      @test !occursin("scale_multipoles", out)

      # A Bmad limit is a distance from the axis, so the low-side ones come out positive:
      # Bmad loses a particle at `x < -x1_limit`, where PALS loses it at `x < x_min`.
      @test occursin("x1_limit = 0.03, x2_limit = 0.05", out)
      @test occursin("y1_limit = 0.01, y2_limit = 0.02", out)

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

      # Beamlines states a limit as an edge position, so the low-side ones stay as PALS
      # wrote them -- where Bmad wants the distance from the axis.
      @test occursin("x1_limit = -0.03, x2_limit = 0.05", out)
      @test occursin("y1_limit = -0.01, y2_limit = 0.02", out)
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

      # ABSOLUTE sets the parameter, so it is an overlay.  `Kn1` is a quadrupole's own
      # strength, which Bmad keeps in `K1` in the same units, so nothing is rescaled.  The
      # variable list and each initial value get a continuation line of their own.
      @test occursin("knob: overlay = {q1[K1]: 2*k},\n\tvar = {k},\n\tk = 0.3\n", out)

      # RELATIVE adds to the parameter, so it is a group.  `Ks2L` is already integrated --
      # no length -- but is skew and second order, hence A2 and the 1/2! of the convention.
      @test occursin("bump: group = {s1[A2]: 0.5*(dk)},\n\tvar = {dk},\n\tdk = 0.0\n", out)

      # q1's strength is its own `K1`, so it has no multipole left to scale.  s1's is skew,
      # which Bmad has no sextupole attribute for, so it stays the multipole `A2` -- and Bmad
      # would otherwise read that as a fraction of s1's strength and scale it by that, i.e. by
      # zero, since the strength is the multipole.
      @test occursin("q1: Quadrupole,\n\tL = 0.5,\n\tK1 = 0.25\n", out)
      @test occursin("A2 = 0.75,\n\tscale_multipoles = F", out)

      # q1's aperture group sets no limit, so it bounds nothing and none of it is written out.
      # s1's does, and Bmad states each limit as a distance from the axis.
      @test occursin("x1_limit = 0.0625, x2_limit = 0.1875", out)
      @test occursin("y1_limit = 0.125, y2_limit = 0.375", out)
      @test occursin("aperture_type = elliptical,\n\taperture_at = both_ends", out)
      @test count("aperture_type", out) == 1

      # An element that is only multipoles does no such scaling, and has no attribute to set.
      @test occursin("m1: AB_Multipole,\n\tB3 = 0.11666666666666665\n", out)

      # The rest of the lattice still comes through.
      @test occursin("ring: line = (q1, s1, m1)", out)
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

      # An aperture group that sets no limit bounds nothing, so q1 gets no aperture at all.
      @test occursin("q1 = LineElement(kind = Quadrupole, L = 0.5, Kn1 = 0.25)", out)

      # s1's does bound something.  Beamlines states each limit as an edge position, so the
      # low-side ones are negative -- where Bmad wants a distance from the axis.
      @test occursin("x1_limit = -0.0625, x2_limit = 0.1875", out)
      @test occursin("y1_limit = -0.125, y2_limit = 0.375", out)
      @test occursin("aperture_shape = ApertureShape.Elliptical, aperture_at = ApertureAt.BothEnds", out)

      # The line names its beginning element; its reference parameters still reach the
      # beamline, and the branch given as a map still reaches the lattice list.
      @test occursin("species_ref = electron", out)
      @test occursin("lat = [ring,]", out)
    end
  end

  @testset "an element's own multipole becomes its Bmad strength attribute" begin
    mktempdir() do dir
      bmad = pals_to_bmad(_parsed(dir, _STRENGTH_FIXTURE))
      out_path = joinpath(dir, "fixture.pals_out.bmad")
      write_bmad_file(bmad, out_path)
      out = read(out_path, String)

      # A quadrupole's order-1 field is its K1, in the same units.  Any other order is a
      # multipole, which is integrated and carries the 1/n!: 0.4 * 0.5 / 3! here.
      @test occursin("q1: Quadrupole,\n\tL = 0.5,\n\tK1 = 0.25,\n\tB3 = 0.03333333333333333,\n\tscale_multipoles = F\n", out)

      # K1 is not length integrated, so an integrated PALS value is divided by the length --
      # and nothing is left over to need the scaling turned off.
      @test occursin("q2: Quadrupole,\n\tL = 2,\n\tK1 = 0.3\n", out)

      # An unnormalized multipole gives the field attribute instead, and field_master with it.
      @test occursin("q3: Quadrupole,\n\tL = 0.5,\n\tfield_master = T,\n\tB1_GRADIENT = 3.0\n", out)

      # Bmad has no skew quadrupole attribute, so a skew multipole stays a multipole: 0.8 * 0.5.
      @test occursin("q4: Quadrupole,\n\tL = 0.5,\n\tA1 = 0.4,\n\tscale_multipoles = F\n", out)

      # A tilt of T on an order-N multipole rotates it by (N+1)*T, so this sextupole turns by
      # 0.3 rad: its normal part is the strength attribute and its skew part a multipole.
      @test occursin("s2: Sextupole,\n\tL = 1,\n\tK2 = 0.9553364", out)   # cos(0.3)
      @test occursin("A2 = -0.1477601", out)                              # -sin(0.3) * 1 / 2!

      # An element that is only multipoles keeps them all: 0.7 / 3!.
      @test occursin("m1: AB_Multipole,\n\tB3 = 0.11666666666666665\n", out)

      # Every control lands on the attribute its element was given, scaled the same way, and
      # each gets a line to itself.
      @test occursin("kk: overlay = {q1[K1]: a,\n\t\tq2[K1]: 0.5*(a),\n\t\tq3[B1_GRADIENT]: a," *
                     "\n\t\tq4[A1]: 0.5*(a),\n\t\tq1[B3]: 0.08333333333333333*(a)}," *
                     "\n\tvar = {a},\n\ta = 1.0\n", out)
    end
  end

  @testset "a bend's order-0 multipole becomes its Bmad DG" begin
    mktempdir() do dir
      bmad = pals_to_bmad(_parsed(dir, _BEND_FIXTURE))
      out_path = joinpath(dir, "fixture.pals_out.bmad")
      write_bmad_file(bmad, out_path)
      out = read(out_path, String)

      # PALS states the bend field outright; Bmad states its departure from the reference bend.
      @test occursin("b1: SBend,\n\tL = 1,\n\tg = 0.5,\n\tDG = 0.25\n", out)

      # A bend whose field is the reference bend departs from it by nothing, so there is no DG to
      # write.  The orders that are not the bend's own are multipoles as they are anywhere else.
      @test occursin("b2: SBend,\n\tL = 1,\n\tg = 0.5,\n\tB1 = 0.2,\n\tscale_multipoles = F\n", out)

      # DG is not length integrated, so an integrated PALS field is divided by the length before
      # the reference comes off it -- and the reference may be given as the radius of the bend.
      @test occursin("b3: SBend,\n\tL = 2,\n\trho = 4,\n\tDG = 0.5\n", out)

      # An unnormalized field is measured against the unnormalized reference, in the same way.
      @test occursin("b4: SBend,\n\tL = 1,\n\tB_field = 2.0,\n\tfield_master = T,\n\tDB_FIELD = 1.0\n", out)

      # An overlay sets DG, so it has to take the reference off what PALS drives.  A group varies
      # DG instead, and the reference it is measured from is the same before and after.
      @test occursin("knob: overlay = {b1[DG]: kk0 - (0.5)},\n\tvar = {kk0},\n\tkk0 = 0.6\n", out)
      @test occursin("bump: group = {b2[DG]: dkk0},\n\tvar = {dkk0},\n\tdkk0 = 0.0\n", out)
    end
  end

  @testset "a bend field and reference of different kinds are reported" begin
    mktempdir() do dir
      # Normalizing one against the other takes the reference momentum, which belongs to the
      # branch rather than to the element.
      @test_throws "are not both normalized" pals_to_bmad(_parsed(dir, _BEND_MISMATCH_FIXTURE))
    end
  end

  @testset "MetaP becomes the Bmad metadata strings" begin
    mktempdir() do dir
      bmad = pals_to_bmad(_parsed(dir, _META_FIXTURE))
      out_path = joinpath(dir, "fixture.pals_out.bmad")
      write_bmad_file(bmad, out_path)
      out = read(out_path, String)

      # Bmad has three metadata strings: alias, type (PALS `label`) and descrip (`description`).
      @test occursin("q1: Quadrupole,\n\tL = 0.5,\n\talias = \"q_one\",\n\ttype = \"AGSBPM\"," *
                     "\n\tdescrip = \"A quadrupole\"\n", out)

      # The components Bmad has no place for are dropped rather than forced into one.
      @test !occursin("0137-85", out)
      @test !occursin("water leak", out)

      # Bmad cannot escape a quote inside a string, so a string holding one of the two quote
      # characters is wrapped in the other.
      @test occursin("q2: Quadrupole,\n\tL = 0.5,\n\ttype = 'has a \" double quote'\n", out)
    end
  end

  @testset "constants and variables become Bmad definitions" begin
    mktempdir() do dir
      bmad = pals_to_bmad(_parsed(dir, _CONSTANT_FIXTURE))
      out_path = joinpath(dir, "fixture.pals_out.bmad")
      write_bmad_file(bmad, out_path)
      out = read(out_path, String)

      # Bmad draws no constant/variable distinction: both are a name with a value, written in
      # definition order because a Bmad name has to be defined above the point of use.  Those
      # defined directly under `PALS` are translated alongside the facility's own.
      @test occursin("c_top = 1.5\nc_one = 0.3\nc_two = 2 * c_one\nv_one = 0.5\nv_two = 0\n" *
                     "m_e = mass_of(\"electron\")\nmy_var = 37\n", out)

      # Which is also why the whole section comes before anything that could use one.
      @test findfirst("c_one = 0.3", out).start < findfirst("parameter[particle]", out).start
      @test findfirst("my_var = 37", out).start < findfirst("q1: Quadrupole", out).start

      # An element parameter given as a constant is carried over as it was written.
      @test occursin("q1: Quadrupole,\n\tL = c_one\n", out)
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
