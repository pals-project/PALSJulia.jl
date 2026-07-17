using Test
using PALSJulia
using PALSJulia: parse_and_expand_pals, evaluate_pals_expression

# A lattice exercising the expression evaluator: user variables, an immediate
# expression, an expr()-delayed expression, a particle-function constant, and a
# random_gauss() value that must stay unevaluated.
const EXPR_LATTICE = """
PALS:
  facility:
    - variables:
        - a_var: 3.75e7 / c_light^2
        - b_var: -0.34
    - cleo:
        kind: Solenoid
        length: 0.1*log(abs(b_var))
        MagneticMultipoleP:
          Kn1: expr(3.74 * a_var)
          Kn2: 0.01 + 0.003*random_gauss()
    - m_e:
        kind: constant
        value: mass_of("electron")
    - main_line:
        kind: BeamLine
        line:
          - cleo
    - lat1:
        kind: Lattice
        branches:
          - main_line
    - use: "lat1"
"""

# A lattice with two controllers: `ps27` has inter-referencing variables and
# controls that use a lattice constant and a deferred random_gauss(); `chrom_a`
# references `ps27`'s variable via the `controller>variable` syntax.
const CONTROLLER_LATTICE = """
PALS:
  facility:
    - my_const:
        kind: constant
        value: 2.0
    - ps27:
        kind: Controller
        control_type: ABSOLUTE
        variables:
          cur1: 0.023
          cur2: cur1 / c_light
        controls:
          - parameter: Qa.*>MagneticMultipoleP.Ks2L
            expression: 0.075*sin(cur1) + 0.3*cur2
          - parameter: Qb>MagneticMultipoleP.Kn1L
            expression: cur1 * my_const
          - parameter: Qc>MagneticMultipoleP.Kn0
            expression: 0.01 + random_gauss()
    - chrom_a:
        kind: Controller
        control_type: RELATIVE
        variables:
          command: 0.4
          derived: ps27>cur1 * 2
        controls:
          - parameter: S1>MagneticMultipoleP.Kn2L
            expression: 5.62 * command + 0.02 * command^2
    - main_line:
        kind: BeamLine
        line:
          - my_const
    - lat1:
        kind: Lattice
        branches:
          - main_line
    - use: "lat1"
"""

# A lattice where one element's parameter references another element's parameter
# via the `element>group.param` syntax inside an expression.
const ELEMENT_PARAM_REF_LATTICE = """
PALS:
  facility:
    - thingB:
        kind: Sextupole
        length: 0.3
        MagneticMultipoleP:
          Kn2L: 0.1
    - DH1A:
        kind: Bend
        length: 0.2
        BendP:
          edge_int2: 0.02 * thingB>MagneticMultipoleP.Kn2L
    - main_line:
        kind: BeamLine
        line:
          - DH1A
    - lat1:
        kind: Lattice
        branches:
          - main_line
    - use: "lat1"
"""

# A lattice that deliberately fails several ways during expansion: an undefined
# constant reference, a dangling element-parameter reference, a dangling line
# reference, and an undefined `inherit` ancestor.
const BROKEN_LATTICE = """
PALS:
  facility:
    - constants:
        a_const: 0.3 * undefined_thing
    - thingB:
        kind: Sextupole
        MagneticMultipoleP:
          Kn2L: 0.1
    - DH1A:
        kind: Bend
        BendP:
          edge_int2: 0.02 * thingB>MagneticMultipoleP.NotThere
    - ghost_child:
        kind: Bend
        inherit: ghost_ancestor
    - main_line:
        kind: BeamLine
        line:
          - DH1A
          - ghost_child
          - NoSuchElement
    - lat1:
        kind: Lattice
        branches:
          - main_line
    - use: "lat1"
"""

# A lattice that names a species with a string constant and feeds it to the
# particle-data functions by symbol (mass_of(species)), not a quoted literal.
const SPECIES_CONST_LATTICE = """
PALS:
  facility:
    - constants:
        species: "#3He"
        b_const: 0.45 * mass_of(species)
    - DH1A:
        kind: Bend
        ReferenceP:
          species_ref: species
        BendP:
          e_tot: 1.1 * mass_of(species)
    - main_line:
        kind: BeamLine
        line:
          - DH1A
    - lat1:
        kind: Lattice
        branches:
          - main_line
    - use: "lat1"
"""

@testset "Expression Evaluation" begin

  @testset "evaluate_pals_expression: standalone" begin
    @test evaluate_pals_expression("2 + 3 * 4") == 14.0
    @test evaluate_pals_expression("2 ^ 3 ^ 2") == 512.0      # right-associative
    @test evaluate_pals_expression("-2 ^ 2") == -4.0          # unary minus looser than ^
    @test evaluate_pals_expression("3.75e7 / c_light^2") ≈ 3.75e7 / (2.99792458e8)^2
    @test evaluate_pals_expression("sqrt(2)") ≈ sqrt(2)
    @test evaluate_pals_expression("modulo(7, 3)") == 1.0
    @test evaluate_pals_expression("pi") ≈ pi
    # expr(...) wrapper is accepted.
    @test evaluate_pals_expression("expr(2 * pi)") ≈ 2pi
  end

  @testset "evaluate_pals_expression: particle-data functions" begin
    # Species names must always be quoted (single or double). Values mirror
    # AtomicAndPhysicalConstantsCLib (CODATA 2022).
    @test evaluate_pals_expression("mass_of(\"electron\")") ≈ 510998.95069000003
    @test evaluate_pals_expression("mass_of('proton')") ≈ 938272089.43000007
    @test evaluate_pals_expression("charge_of(\"electron\")") == -1.0
    @test evaluate_pals_expression("charge_of(\"anti-proton\")") == -1.0
    @test evaluate_pals_expression("charge_of(\"helion\")") == 2.0
    # A mass number must carry a leading `#` (e.g. "#3He", not "3He").
    @test evaluate_pals_expression("mass_of(\"#3He\")") ≈ 2809413524.398952
    @test_throws ArgumentError evaluate_pals_expression("mass_of(\"3He\")")
  end

  @testset "evaluate_pals_expression: non-evaluable inputs throw" begin
    @test_throws ArgumentError evaluate_pals_expression("thingB")            # unknown identifier
    @test_throws ArgumentError evaluate_pals_expression("mass_of(\"nonsense\")") # unknown species
    @test_throws ArgumentError evaluate_pals_expression("mass_of(electron)") # unquoted species
    @test_throws ArgumentError evaluate_pals_expression("0.01 + random_gauss()")  # deferred
    @test_throws ArgumentError evaluate_pals_expression("1 +")              # parse error
  end

  # The element `name` as expansion inlined it into `lat.expanded`. The expanded
  # tree is rooted at the lattice entry, so the path runs
  # lattice > branches > beamline > line > element, with no PALS/facility above.
  inlined(lat, lattice, beamline, name) =
    lat.expanded[lattice]["branches"][1][beamline]["line"][1][name]

  @testset "parse_and_expand_pals evaluates the expanded tree" begin
    mktempdir() do dir
      path = joinpath(dir, "expr.pals.yaml")
      write(path, EXPR_LATTICE)
      lat = parse_and_expand_pals(path)

      a_var = 3.75e7 / (2.99792458e8)^2
      # cleo is named by main_line, so its definition is inlined into lat1.
      cleo = inlined(lat, "lat1", "main_line", "cleo")
      mmp = cleo["MagneticMultipoleP"]

      # Immediate expression using a user variable.
      @test Float64(cleo["length"]) ≈ 0.1 * log(0.34)
      # expr()-delayed expression is evaluated to a number in the expanded tree.
      @test Float64(mmp["Kn1"]) ≈ 3.74 * a_var
      # random_gauss() is deferred: the text is left untouched.
      @test String(mmp["Kn2"]) == "0.01 + 0.003*random_gauss()"

      # m_e is not part of the lattice and nothing in it refers to m_e, so it is
      # left over — evaluated all the same.
      @test Float64(lat.leftover["PALS"]["facility"][3]["m_e"]["value"]) ≈
            510998.95069000003

      # The combined tree keeps the original expression text.
      @test String(lat.combined["PALS"]["facility"][2]["cleo"]["length"]) ==
            "0.1*log(abs(b_var))"
    end
  end

  @testset "parse_and_expand_pals resolves element-parameter references" begin
    mktempdir() do dir
      path = joinpath(dir, "eleparamref.pals.yaml")
      write(path, ELEMENT_PARAM_REF_LATTICE)
      lat = parse_and_expand_pals(path)

      # edge_int2 references thingB's Kn2L (0.1) via element>group.param syntax.
      dh1a = inlined(lat, "lat1", "main_line", "DH1A")
      @test Float64(dh1a["BendP"]["edge_int2"]) ≈ 0.02 * 0.1
    end
  end

  @testset "parse_and_expand_pals resolves a species-name constant" begin
    mktempdir() do dir
      path = joinpath(dir, "species.pals.yaml")
      write(path, SPECIES_CONST_LATTICE)
      lat = parse_and_expand_pals(path; problems=:none)

      m_3he = evaluate_pals_expression("mass_of(\"#3He\")")
      # The constants block is not part of the lattice, so it is left over.
      consts = lat.leftover["PALS"]["facility"][1]["constants"]
      dh1a = inlined(lat, "lat1", "main_line", "DH1A")

      # mass_of(species) resolves the `species: "#3He"` constant by name.
      @test Float64(consts["b_const"]) ≈ 0.45 * m_3he
      @test Float64(dh1a["BendP"]["e_tot"]) ≈ 1.1 * m_3he
      # A bare identifier naming the species constant (species_ref: species) is
      # replaced by its species-name string in the expanded tree.
      @test String(dh1a["ReferenceP"]["species_ref"]) == "#3He"
      # The species constant itself keeps its string species name.
      @test String(consts["species"]) == "#3He"
    end
  end

  @testset "parse_and_expand_pals evaluates controllers" begin
    mktempdir() do dir
      path = joinpath(dir, "controller.pals.yaml")
      write(path, CONTROLLER_LATTICE)
      lat = parse_and_expand_pals(path)

      cur1 = 0.023
      cur2 = cur1 / 2.99792458e8
      # Controllers are facility-level, so they are left over rather than part of
      # the lattice; their expressions are evaluated all the same.
      fac = lat.leftover["PALS"]["facility"]
      ps27 = fac[2]["ps27"]

      # A controller variable evaluated with the controller's own symbol table:
      # cur2 references the earlier variable cur1 and the constant c_light.
      @test Float64(ps27["variables"]["cur2"]) ≈ cur2
      # Each control expression is computed and stored back in the entry.
      @test Float64(ps27["controls"][1]["expression"]) ≈ 0.075*sin(cur1) + 0.3*cur2
      # Control expressions may reference lattice constants (my_const = 2).
      @test Float64(ps27["controls"][2]["expression"]) ≈ cur1 * 2.0
      # random_gauss() stays deferred.
      @test String(ps27["controls"][3]["expression"]) == "0.01 + random_gauss()"
      # The parameter target spec is a name, left untouched.
      @test String(ps27["controls"][1]["parameter"]) == "Qa.*>MagneticMultipoleP.Ks2L"

      # A second controller referencing the first's variable via `name>var`.
      chrom = fac[3]["chrom_a"]
      @test Float64(chrom["variables"]["derived"]) ≈ cur1 * 2.0
      @test Float64(chrom["controls"][1]["expression"]) ≈ 5.62*0.4 + 0.02*0.4^2

      # The combined tree keeps the original controller expression text.
      c_ps27 = lat.combined["PALS"]["facility"][2]["ps27"]
      @test String(c_ps27["controls"][1]["expression"]) == "0.075*sin(cur1) + 0.3*cur2"
    end
  end

  @testset "parse_and_expand_pals reports expansion problems" begin
    mktempdir() do dir
      # Run `f` with stderr redirected to a temp file; return what was written.
      capture_stderr(f) = begin
        log = joinpath(dir, "stderr.log")
        open(log, "w") do io
          redirect_stderr(f, io)
        end
        read(log, String)
      end

      path = joinpath(dir, "broken.pals.yaml")
      write(path, BROKEN_LATTICE)

      # A clean lattice prints nothing by default.
      clean = joinpath(dir, "clean.pals.yaml")
      write(clean, ELEMENT_PARAM_REF_LATTICE)
      @test isempty(capture_stderr(() -> parse_and_expand_pals(clean)))

      # `:print` (default) writes the problems to stderr.
      printed = capture_stderr(() -> parse_and_expand_pals(path))
      @test occursin("problem(s)", printed)
      @test occursin("NoSuchElement", printed)

      # A filename writes the problems to that file and prints nothing.
      report = joinpath(dir, "problems.txt")
      @test isempty(capture_stderr(() -> parse_and_expand_pals(path; problems=report)))
      contents = read(report, String)
      @test occursin("reference to undefined element or line 'NoSuchElement'", contents)
      @test occursin("inherit: 'ghost_ancestor' is not defined", contents)
      @test occursin("could not evaluate expression for constants.a_const", contents)
      @test occursin("could not evaluate expression for BendP.edge_int2", contents)

      # `:none` prints nothing.
      @test isempty(capture_stderr(() -> parse_and_expand_pals(path; problems=:none)))

      # An invalid `problems` value is rejected.
      @test_throws ArgumentError parse_and_expand_pals(path; problems=:bogus)
    end
  end

end
