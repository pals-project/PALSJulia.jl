using Test
# pals_to_bmad / write_bmad_file, pals_to_madx / write_madx_file and
# pals_to_scibmad / write_scibmad_file are exported.
using PALSJulia
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

# `_STRENGTH_FIXTURE` without the control that drives a quadrupole's order-3 multipole. Bmad
# keeps that one in a `B3` of its own, but a MAD-X quadrupole has no attribute for it at all,
# and no way to name one entry of a multipole array, so the control has nowhere to land.
const _MADX_STRENGTH_FIXTURE =
    replace(_STRENGTH_FIXTURE,
            r"\n *- parameter: q1>MagneticMultipoleP\.Kn3\n *expression: a" => "")

# A misaligned element and an RF cavity, for the two things MAD-X keeps outside an element
# definition or states in units of its own.  MAD-X has no controller scope either, so `knob`
# and `bump` name the same variable, which is two independent knobs in PALS and one in MAD-X.
const _MADX_ALIGN_FIXTURE = """
  PALS:
    facility:
      - beg:
          kind: BeginningEle
          ReferenceP:
            species_ref: electron
            pc_ref: 3E9
      - q1:
          kind: Quadrupole
          length: 0.5
          BodyShiftP:
            x_offset: 1e-4
            x_rot: 2e-4
            y_rot: 3e-4
            z_rot: 4e-4
      - rf1:
          kind: RFCavity
          length: 1.3
          RFP:
            frequency: 5E8
            voltage: 1E6
            phase: 0.1
            zero_phase: ABOVE_TRANSITION
      - ring:
          kind: BeamLine
          line:
            - beg
            - q1
            - rf1
      - lat:
          kind: Lattice
          branches:
            - ring:
                periodic: true
  """

# A bend for each pair of the three sets of mutually dependent geometry parameters PALS allows
# -- a curvature, a length, and the angle -- since MAD-X wants one particular pair of them, the
# angle and the arc length.  b2 also has its entrance face given the rectangular way and its
# exit face the sector way; b3's `ref_geometry` puts the whole angle on one face rather than
# splitting it; and b4 states a bend that has the reference geometry but no field of its own.
const _MADX_GEOMETRY_FIXTURE = """
  PALS:
    facility:
      - beg:
          kind: BeginningEle
          ReferenceP:
            species_ref: electron
            pc_ref: 3E9
      - b1:
          kind: Bend
          BendP:
            angle_ref: 0.25
            g_ref: 0.5
      - b2:
          kind: Bend
          length: 2
          BendP:
            g_ref: 0.25
            e1_rect: 0.01
            e2: 0.3
      - b3:
          kind: Bend
          BendP:
            angle_ref: 0.4
            L_chord: 1.5
            ref_geometry: EXIT_COORDS
            e1_rect: 0.02
            e2_rect: 0.03
      - b4:
          kind: Bend
          length: 1
          BendP:
            g_ref: 0.3
            Kn0_from_g_ref: false
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

# `_MADX_ALIGN_FIXTURE` with two controllers that each own a variable called `kq`, which PALS
# scopes to its controller and MAD-X does not scope at all.  The second is RELATIVE and rests
# at a setting where its expression does not come to zero, which is the case a MAD-X deferred
# assignment cannot state without saying where the knob started.
# (Written with explicit newlines: a triple-quoted string would have its indentation stripped
# to the shallowest line, which is not the indentation the surrounding fixture is at.  The
# leading newline anchors the match to the facility entry, not to the one under `branches:`.)
const _MADX_CLASH_FIXTURE =
    replace(_MADX_ALIGN_FIXTURE, "\n    - ring:" =>
            "\n    - knob:\n        kind: Controller\n        MetaP:\n" *
            "          description: Model Mitsubishi 800KL\n" *
            "        variables:\n          kq: 0.3\n" *
            "        controls:\n          - parameter: q1>length\n            expression: 2*kq\n" *
            "    - other:\n        kind: Controller\n        control_type: RELATIVE\n" *
            "        variables:\n          kq: 0.5\n" *
            "        controls:\n          - parameter: rf1>length\n            expression: 4*kq\n" *
            "    - ring:")

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

  @testset "pals_to_madx / write_madx_file writes a MAD-X lattice file" begin
    mktempdir() do dir
      madx = pals_to_madx(_parsed(dir, _TRANSLATE_FIXTURE))
      out_path = joinpath(dir, "fixture.pals_out.madx")
      write_madx_file(madx, out_path)

      @test isfile(out_path)
      out = read(out_path, String)

      # BeginningEle → the BEAM command. MAD-X states the reference energy in GeV where PALS
      # states it in eV, and takes the species first and works the rest out from it.
      @test occursin("beam, particle = electron, pc = 0.003;", out)

      # TwissP → a BETA0 block, which is where MAD-X takes initial conditions from.
      @test occursin("pals_beta0: beta0,\n\tbetx = 10,\n\talfx = 0.5;", out)

      # ParticleP → the START command of the TRACK module, which has no place in a lattice
      # file, so it is written out as a comment rather than as a command.
      @test occursin("!   start, x = 1, px = 4;", out)

      # Ordinary element definitions. Every MAD-X statement ends in a semicolon.
      @test occursin("d1: drift,\n\tl = 100;", out)
      @test occursin("q1: quadrupole,\n\tl = 0.5;", out)

      # MAD-X is the one format of the three that cannot put an aperture on a drift, so d1's
      # is reported rather than written out.
      @test !occursin("aperture", out)

      # Beamline definition (line[1] is dropped by design, leaving d1, q1).
      @test occursin("ring: line = (d1, q1);", out)

      # MAD-X has no geometry attribute: whether a branch closes on itself is decided by how
      # it is used, so the flag is carried across as a comment beside the `use`.
      @test occursin("use, period = ring;\t! open", out)

      # Nothing here states a field rather than a normalized strength, so the rigidity that
      # would normalize one is not defined.
      @test !occursin("pals_brho", out)
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

  @testset "a Controller becomes MAD-X variables and deferred assignments" begin
    mktempdir() do dir
      madx = pals_to_madx(_parsed(dir, _CONTROLLER_FIXTURE))
      out_path = joinpath(dir, "fixture.pals_out.madx")
      write_madx_file(madx, out_path)
      out = read(out_path, String)

      # MAD-X has no controller element. A variable and the deferred `:=` that makes an
      # attribute depend on it are what it has instead, and are what a controller becomes.
      # `Kn1` is a quadrupole's own strength, which MAD-X keeps in `k1` in the same units.
      @test occursin("! Controller knob\nk = 0.3;\nq1->k1 := 2*k;", out)

      # RELATIVE adds to the parameter. A deferred assignment can only set one -- MAD-X
      # forbids the circular `s1->k2s := s1->k2s + ...` -- so what is being added to has to be
      # written into the assignment, and it is the value the element definition already has.
      # `Ks2L` is integrated and MAD-X's `k2s` is not, hence the 1/0.2 on both.
      @test occursin("s1: sextupole,\n\tl = 0.2,\n\tk2s = 7.5", out)
      @test occursin("! Controller bump\ndk = 0.0;\ns1->k2s := 7.5 + (5.0*(dk));", out)

      # Unlike Bmad, MAD-X has a skew attribute for each of these orders, so a skew multipole
      # of the element's own order needs no multipole element of its own -- and nothing needs
      # its scaling turned off, MAD-X reading no multipole as a fraction of anything.
      @test occursin("q1: quadrupole,\n\tl = 0.5,\n\tk1 = 0.25;", out)

      # q1's aperture group sets no limit, so it bounds nothing and none of it is written out.
      # s1's does: MAD-X states a half extent about the axis and the offset of the centre,
      # where PALS states the two edges or a width and a centre.
      @test occursin("aperture = {0.125, 0.25},\n\taper_offset = {0.0625, 0.125}," *
                     "\n\tapertype = ellipse;", out)
      @test count("apertype", out) == 1

      # An element that is only multipoles is a MAD-X multipole, whose coefficients are the
      # integrated ones indexed by order from zero up, with the gaps filled in.
      @test occursin("m1: multipole,\n\tknl = {0, 0, 0, 0.7};", out)

      # The rest of the lattice still comes through.
      @test occursin("ring: line = (q1, s1, m1);", out)
      @test occursin("use, period = ring;", out)
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

  @testset "an element's own multipole becomes its MAD-X strength attribute" begin
    mktempdir() do dir
      madx = pals_to_madx(_parsed(dir, _MADX_STRENGTH_FIXTURE))
      out_path = joinpath(dir, "fixture.pals_out.madx")
      write_madx_file(madx, out_path)
      out = read(out_path, String)

      # A quadrupole's order-1 field is its k1, in the same units: unlike Bmad's An/Bn, a
      # MAD-X coefficient carries no 1/n!, and neither does a PALS one. Any other order has
      # nowhere to go on a MAD-X quadrupole and is reported rather than written out.
      @test occursin("q1: quadrupole,\n\tl = 0.5,\n\tk1 = 0.25;", out)

      # k1 is not length integrated, so an integrated PALS value is divided by the length.
      @test occursin("q2: quadrupole,\n\tl = 2,\n\tk1 = 0.3;", out)

      # MAD-X has no field-valued strength attribute at all, so an unnormalized multipole is
      # divided by the rigidity -- which MAD-X works out for itself from the BEAM command.
      @test occursin("pals_brho := beam->brho * beam->charge / abs(beam->charge);", out)
      @test occursin("q3: quadrupole,\n\tl = 0.5,\n\tk1 = 3.0 / pals_brho;", out)

      # MAD-X does have a skew quadrupole attribute, where Bmad keeps a skew multipole a
      # multipole, so nothing is left over and no length goes into it.
      @test occursin("q4: quadrupole,\n\tl = 0.5,\n\tk1s = 0.8;", out)

      # A tilt of T on an order-N multipole rotates it by (N+1)*T, so this sextupole turns by
      # 0.3 rad: its normal part is k2 and its skew part k2s, and MAD-X's own tilt -- which
      # would turn the whole element -- is left alone.
      @test occursin("s2: sextupole,\n\tl = 1,\n\tk2 = 0.9553364", out)   # cos(0.3)
      @test occursin("k2s = -0.2955202", out)                             # -sin(0.3)

      # An element that is only multipoles keeps them all, integrated and without a factorial.
      @test occursin("m1: multipole,\n\tknl = {0, 0, 0, 0.7};", out)

      # Every control lands on the attribute its element was given, scaled the same way.
      @test occursin("! Controller kk\na = 1.0;\nq1->k1 := a;\nq2->k1 := 0.5*(a);" *
                     "\nq3->k1 := (a) / pals_brho;\nq4->k1s := a;", out)
    end
  end

  @testset "a control MAD-X has no attribute for is reported" begin
    mktempdir() do dir
      # Bmad keeps a quadrupole's order-3 multipole in a B3 of its own. A MAD-X quadrupole
      # has no such attribute, and MAD-X has no way to name one entry of a multipole array,
      # so a control aimed there has nowhere to land.
      @test_throws "has no attribute for" pals_to_madx(_parsed(dir, _STRENGTH_FIXTURE))
    end
  end

  @testset "a bend's order-0 multipole becomes its MAD-X angle" begin
    mktempdir() do dir
      madx = pals_to_madx(_parsed(dir, _BEND_FIXTURE))
      out_path = joinpath(dir, "fixture.pals_out.madx")
      write_madx_file(madx, out_path)
      out = read(out_path, String)

      # MAD-X builds a bend out of its angle, however PALS chose to state the same geometry:
      # as a curvature here, as a radius for b3, as a field for b4.
      @test occursin("b1: sbend,\n\tl = 1,\n\tangle = 0.5;", out)
      @test occursin("b3: sbend,\n\tl = 2,\n\tangle = 0.5;", out)
      @test occursin("b4: sbend,\n\tl = 1,\n\tangle = 2.0 / pals_brho;", out)

      # MAD-X has the one `angle` for the geometry and the field both, so a field that agrees
      # with the reference bend has nothing left to state, and one that disagrees -- b1, b3
      # and b4 -- is reported rather than written out, which would move everything downstream.
      # The orders that are not the bend's own are its own attributes here too.
      @test occursin("b2: sbend,\n\tl = 1,\n\tangle = 0.5,\n\tk1 = 0.2;", out)
      @test !occursin("angle = 0.75", out)
      @test !occursin("angle = 1.5", out)

      # A control on the field is a control on that same angle: `Kn0` is not integrated and
      # the angle is, so the length goes in -- which is 1 for b1, hence no factor.
      @test occursin("! Controller knob\nkk0 = 0.6;\nb1->angle := kk0;", out)
      @test occursin("! Controller bump\ndkk0 = 0.0;\nb2->angle := 0.5 + (dkk0);", out)
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

  @testset "MetaP becomes MAD-X comments" begin
    mktempdir() do dir
      madx = pals_to_madx(_parsed(dir, _META_FIXTURE))
      out_path = joinpath(dir, "fixture.pals_out.madx")
      write_madx_file(madx, out_path)
      out = read(out_path, String)

      # A MAD-X element holds no metadata of its own -- there is no attribute to put any of
      # this in -- so what PALS says about an element is kept as a comment above it. That
      # leaves room for the components Bmad has to drop, and for a quote character that Bmad,
      # having no escape for one, cannot always write.
      @test occursin("! alias: q_one\n! label: AGSBPM\n! description: A quadrupole" *
                     "\n! ID: 0137-85\nq1: quadrupole,", out)
      @test occursin("! label: has a \" double quote\nq2: quadrupole,", out)

      # A component holding a structure rather than a string still has nowhere to go.
      @test !occursin("water leak", out)
    end
  end

  @testset "constants and variables become MAD-X definitions" begin
    mktempdir() do dir
      madx = pals_to_madx(_parsed(dir, _CONSTANT_FIXTURE))
      out_path = joinpath(dir, "fixture.pals_out.madx")
      write_madx_file(madx, out_path)
      out = read(out_path, String)

      # MAD-X draws no constant/variable distinction either: both are a name with a value,
      # written in definition order because a MAD-X name has to be defined above the point of
      # use. Those defined directly under `PALS` are translated alongside the facility's own.
      @test occursin("c_top = 1.5;\nc_one = 0.3;\nc_two = 2 * c_one;\nv_one = 0.5;" *
                     "\nv_two = 0;\nm_e = mass_of(\"electron\");\nmy_var = 37;\n", out)

      # Which is also why the whole section comes before anything that could use one.
      @test findfirst("c_one = 0.3", out).start < findfirst("beam, particle", out).start
      @test findfirst("my_var = 37", out).start < findfirst("q1: quadrupole", out).start

      # An element parameter given as a constant is carried over as it was written.
      @test occursin("q1: quadrupole,\n\tl = c_one;", out)
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

  @testset "a BodyShiftP becomes a MAD-X EALIGN, and RF takes MAD-X's units" begin
    mktempdir() do dir
      madx = pals_to_madx(_parsed(dir, _MADX_ALIGN_FIXTURE))
      out_path = joinpath(dir, "fixture.pals_out.madx")
      write_madx_file(madx, out_path)
      out = read(out_path, String)

      # MAD-X keeps a misalignment out of the element definition and in an EALIGN of its own,
      # applied to whatever the SELECT before it picked out. Its DPHI turns the element the
      # other way round from the right-hand rule the other two angles follow.
      @test occursin("q1: quadrupole,\n\tl = 0.5;", out)
      @test occursin("select, flag = error, clear;\n" *
                     "select, flag = error, pattern = \"^q1\$\";\n" *
                     "ealign, dx = 1e-4, dphi = -0.0002, dtheta = 3e-4, dpsi = 4e-4;", out)

      # Which is also why the EALIGN can only come after the sequence has been expanded.
      @test findfirst("use, period = ring;", out).start < findfirst("ealign,", out).start

      # MAD-X states a frequency in MHz and a voltage in MV where PALS states Hz and volts,
      # and its zero lag is half a period from the stable point above transition.
      @test occursin("rf1: rfcavity,\n\tl = 1.3,\n\tfreq = 500.0,\n\tvolt = 1.0," *
                     "\n\tlag = -0.4;", out)

      # A branch that closes on itself is not something MAD-X states in the lattice.
      @test occursin("use, period = ring;\t! closed", out)
    end
  end

  @testset "a bend's geometry becomes MAD-X's angle and arc length" begin
    mktempdir() do dir
      madx = pals_to_madx(_parsed(dir, _MADX_GEOMETRY_FIXTURE))
      out_path = joinpath(dir, "fixture.pals_out.madx")
      write_madx_file(madx, out_path)
      out = read(out_path, String)

      # PALS states a bend's geometry with any two of a curvature, a length and the angle;
      # MAD-X wants one particular pair, the angle and the arc length, so the pair given has
      # to be turned into that pair. Here: angle and curvature, so the arc is 0.25/0.5.
      @test occursin("b1: sbend,\n\tl = 0.5,\n\tangle = 0.25;", out)

      # Curvature and arc length, so the angle is 0.25*2 -- and the entrance face, given the
      # rectangular way, is e1_rect + angle/2 while the exit face was given the sector way
      # MAD-X measures an sbend against and comes straight across.
      @test occursin("b2: sbend,\n\tl = 2,\n\tangle = 0.5,\n\te1 = 0.26,\n\te2 = 0.3;", out)

      # Angle and chord length, so the arc is angle*L_chord/(2 sin(angle/2)). With
      # ref_geometry EXIT_COORDS the whole angle lands on the entrance face and none on the
      # exit face, rather than being split between them.
      @test occursin("b3: sbend,\n\tl = 1.5100468", out)
      @test occursin("e1 = 0.42", out)
      @test occursin("e2 = 0.03;", out)
    end
  end

  @testset "controller variables are scoped into MAD-X's one namespace" begin
    mktempdir() do dir
      madx = pals_to_madx(_parsed(dir, _MADX_CLASH_FIXTURE))
      out_path = joinpath(dir, "fixture.pals_out.madx")
      write_madx_file(madx, out_path)
      out = read(out_path, String)

      # A PALS controller owns its variables, so `knob>kq` and `other>kq` are two independent
      # knobs. A MAD-X variable is a name in the one namespace the whole file shares, so a
      # name two controllers both claim is prefixed with the controller that owns it -- and
      # the expressions that use it are rewritten to match.
      @test occursin("knob__kq = 0.3;\nq1->l := 2*knob__kq;", out)
      @test occursin("other__kq = 0.5;", out)

      # A controller can carry a MetaP, which MAD-X has nowhere to put but a comment.
      @test occursin("! Controller knob\n! description: Model Mitsubishi 800KL", out)

      # A RELATIVE controller is a knob: its slave keeps the value the lattice gave it and
      # moves by how far the knob has turned *from where it started*. A Bmad group keeps track
      # of that by itself; MAD-X has to be told, and `4*kq` is not zero at kq = 0.5.
      @test occursin("rf1->l := 1.3 + (4*other__kq) - (4*(0.5));", out)
    end
  end

  @testset "a control target no translator can express is reported" begin
    mktempdir() do dir
      yaml = _parsed(dir, _PATTERN_FIXTURE)
      @test_throws "selects slaves by pattern" pals_to_bmad(yaml)
      @test_throws "selects slaves by pattern" pals_to_madx(yaml)
      @test_throws "selects slaves by pattern" pals_to_scibmad(yaml)
    end
  end

end
