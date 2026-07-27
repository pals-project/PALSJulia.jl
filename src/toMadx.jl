"""
    _MADX_RIGIDITY

The name of the MAD-X variable holding the *signed* magnetic rigidity `P0/q` of the reference
particle, which the translation writes out when a lattice states a field rather than a
normalized strength.

MAD-X has no field-valued strength attribute: every magnet strength it holds is normalized. A
PALS field therefore has to be divided by the rigidity here, which MAD-X can compute for itself
from the `BEAM` command: `beam->brho` is `P0/|q|`, so the sign of the charge has to be put back
(see [`_madx_beam`](@ref)).
"""
const _MADX_RIGIDITY = "pals_brho"

#---------------------------------------------------------------------------------------------------
"""
    _MADX_BETA

The MAD-X expression for the relativistic `beta` of the reference particle.

MAD-X measures the longitudinal coordinates and the dispersion against `pt = dE/(p0 c)` where
PALS measures them against `pz = dp/p0`, and the two differ by exactly this factor
(`pt = beta * pz`). MAD-X computes it from the `BEAM` command, so the conversion can be left as
an expression rather than worked out here.
"""
const _MADX_BETA = "beam->beta"

#---------------------------------------------------------------------------------------------------
"""
    _MADX_KEYWORDS

The MAD-X keywords that may not be used as a label.

MAD-X protects its keywords: a lattice whose element is named after one is a fatal error there
rather than here, so the translation reports it instead. The list holds the element-type
keywords and the commands a lattice file is likely to collide with, not every MAD-X command.
"""
const _MADX_KEYWORDS = Set([
    "marker", "drift", "sbend", "rbend", "dipedge", "quadrupole", "sextupole", "octupole",
    "multipole", "solenoid", "nllens", "hkicker", "vkicker", "kicker", "tkicker", "rfcavity",
    "twcavity", "rfmultipole", "crabcavity", "hacdipole", "vacdipole", "elseparator",
    "hmonitor", "vmonitor", "monitor", "instrument", "placeholder", "collimator",
    "ecollimator", "rcollimator", "beambeam", "wire", "matrix", "yrotation", "xrotation",
    "srotation", "translation", "changeref", "sixmarker",
    "line", "sequence", "beam", "beta0", "use", "select", "twiss", "track", "survey", "match",
    "ealign", "efcomp", "eoption", "value", "show", "option", "title", "call", "return"])

#---------------------------------------------------------------------------------------------------
"""
    MadxEleDef

A single MAD-X element definition.

Fields:
  - `name`  : the element name.
  - `type`  : the MAD-X element-type keyword (e.g. `drift`, `quadrupole`).
  - `attrs` : already-translated attribute fragments, each an `"attribute = value"` string.
  - `notes` : comment lines to write above the definition. MAD-X elements carry no metadata
              strings of their own, so a PALS `MetaP` becomes a comment here, as does anything
              else worth saying about the element in the file it is written to.
"""
struct MadxEleDef
  name::String
  type::String
  attrs::Vector{String}
  notes::Vector{String}
end

#---------------------------------------------------------------------------------------------------
"""
    MadxBeamline

A MAD-X `line` definition: its `name` and the ordered list of member element `members` (by name).
"""
struct MadxBeamline
  name::String
  members::Vector{String}
end

#---------------------------------------------------------------------------------------------------
"""
    MadxController

A MAD-X rendering of a PALS `Controller`.

MAD-X has no controller element. What it has instead is the deferred assignment `:=`, which
makes an element attribute depend on a variable rather than take its value once, and that is
what a controller becomes: its variables become ordinary MAD-X variables and each of its
controls becomes a deferred assignment to the attribute it drives.

Fields:
  - `name`     : the controller name, written out as a comment heading.
  - `vars`     : the variables' initial values, each a `"name = value"` string.
  - `controls` : the deferred assignments, each an `"ele->attribute := expression"` string.
  - `notes`    : comment lines to write above the definitions, holding the controller's `MetaP`.
"""
struct MadxController
  name::String
  vars::Vector{String}
  controls::Vector{String}
  notes::Vector{String}
end

#---------------------------------------------------------------------------------------------------
"""
    MadxAlignment

The misalignment of one element: what a PALS `BodyShiftP` becomes.

MAD-X keeps a misalignment apart from the element definition, in an `EALIGN` command applied to
whatever the preceding `SELECT, FLAG=ERROR` picked out. `name` is the element the errors belong
to and `attrs` the `EALIGN` attribute fragments.
"""
struct MadxAlignment
  name::String
  attrs::Vector{String}
end

#---------------------------------------------------------------------------------------------------
"""
    MadxLattice

An in-memory model of a MAD-X lattice.

Produced by [`pals_to_madx`](@ref) and serialized to a file by [`write_madx_file`](@ref).
The fields mirror the sections of a MAD-X lattice file:
  - `constants`      : `name = value;` definitions, in definition order.
  - `beam`           : the attributes of the `BEAM` command (species and energy).
  - `beta0`          : the attributes of the initial-conditions `BETA0` block (Twiss and
                       dispersion).
  - `particle_start` : initial particle coordinates, which MAD-X takes in the `TRACK` module
                       rather than in a lattice file, and which are written out as a comment.
  - `elements`       : element definitions ([`MadxEleDef`](@ref)).
  - `controllers`    : variables and deferred assignments ([`MadxController`](@ref)).
  - `alignments`     : `EALIGN` misalignments ([`MadxAlignment`](@ref)).
  - `beamlines`      : `line` definitions ([`MadxBeamline`](@ref)).
  - `use`            : the branches, each a `name => periodic` pair, for the `use` statement.
  - `rigidity`       : whether anything written refers to [`_MADX_RIGIDITY`](@ref), which then
                       has to be defined ahead of it.
"""
mutable struct MadxLattice
  constants::Vector{String}
  beam::Vector{String}
  beta0::Vector{String}
  particle_start::Vector{String}
  elements::Vector{MadxEleDef}
  controllers::Vector{MadxController}
  alignments::Vector{MadxAlignment}
  beamlines::Vector{MadxBeamline}
  use::Vector{Pair{String,Bool}}
  rigidity::Bool
end
MadxLattice() = MadxLattice(String[], String[], String[], String[], MadxEleDef[],
                            MadxController[], MadxAlignment[], MadxBeamline[],
                            Pair{String,Bool}[], false)

#---------------------------------------------------------------------------------------------------
"""
    pals_to_madx(yaml::YAMLNode)

Translate a parsed PALS lattice `yaml` (as returned by [`parse_file`](@ref)) into a
[`MadxLattice`](@ref).

The returned structure is an in-memory model of the *MAD-X* lattice (elements, lines, beam),
not the input PALS tree. Translation is a three-step process: parse the PALS file with
`parse_file`, build the target model with `pals_to_madx`, then emit the MAD-X lattice file with
[`write_madx_file`](@ref):

```julia
yaml = parse_file(file_dir)
write_madx_file(pals_to_madx(yaml), filename)
```

Controllers are translated after the elements, in a second pass: a `control_type: RELATIVE`
controller adds to the value the element already carries, and the only place that value is
written down is the element definition this pass has just built.
"""
function pals_to_madx(yaml::YAMLNode)
  pals = yaml["PALS"]
  facility = pals["facility"]
  lat = MadxLattice()

  # Constants and variables may be defined directly under `PALS` as well as in the facility.
  for key in ("constants", "variables")
    haskey(pals, key) && append!(lat.constants, _madx_constants(pals[key]))
  end

  N_lattices = 0
  controllers = YAMLNode[]
  for ele in facility
    props = ele[1]
    # The compact `constants:`/`variables:` list is a facility entry in its own right, with no
    # `kind` of its own; every other entry the translation looks at is a named element.
    if node_key(props) in ("constants", "variables")
      append!(lat.constants, _madx_constants(props))
      continue
    end
    haskey(props, "kind") || continue
    pals_kind = String(props["kind"])
    if pals_kind == "BeginningEle"
      beam, beta0, particle = _ele_to_madx_str(ele)
      append!(lat.beam, beam)
      append!(lat.beta0, beta0)
      append!(lat.particle_start, particle)
    elseif pals_kind == "BeamLine"
      push!(lat.beamlines, _make_madx_line(ele, facility))
    elseif pals_kind == "Lattice"
      N_lattices += 1
      N_lattices > 1 && error("\n
                Different BeamLine complexes must be translated from separate files.\n
                A MAD-X run expands one sequence at a time.\n")
      _add_madx_branches!(lat, props["branches"])
    elseif pals_kind == "Controller"
      push!(controllers, ele)
    elseif pals_kind == "constant" || pals_kind == "variable"
      push!(lat.constants, _madx_constant(props, pals_kind))
    else
      def, align = _make_madx_ele(ele)
      push!(lat.elements, def)
      isempty(align.attrs) || push!(lat.alignments, align)
      any(a -> occursin(_MADX_RIGIDITY, a), def.attrs) && (lat.rigidity = true)
    end
  end

  # A PALS controller owns its variables and MAD-X has no such scope, so what each one is
  # called in the file has to be settled before any of them is written out or referred to.
  varmap, initials = _madx_variable_names(controllers, lat.constants)
  for ele in controllers
    push!(lat.controllers, _make_madx_controller(ele, facility, lat, varmap, initials))
  end
  _check_madx_variables(lat)
  any(c -> any(s -> occursin(_MADX_RIGIDITY, s), c.controls), lat.controllers) &&
      (lat.rigidity = true)

  return lat
end

#---------------------------------------------------------------------------------------------------
"""
    _madx_definition_name(defn::AbstractString)

Return the name a `"name = value"` definition defines.
"""
_madx_definition_name(defn::AbstractString) = String(strip(first(split(defn, "="))))

#---------------------------------------------------------------------------------------------------
"""
    _madx_variable_names(controllers::Vector{YAMLNode}, constants::Vector{String})

Decide what each controller variable is called in the MAD-X file.

Return `(names, initials)` where `names` maps a `(controller, variable)` pair to its MAD-X name
and `initials` maps that MAD-X name to the variable's initial value.

A PALS controller owns its variables: `ps1>cur` and `ps2>cur` are two independent knobs, and the
standard's own example uses exactly that. A MAD-X variable is a name in the one namespace the
whole file shares, so a variable whose bare name is claimed by another controller, or by a
constant, is prefixed with the controller that owns it. One that is claimed by nobody else keeps
its bare name, which is what nearly every lattice will have and is far the easier to read.
"""
function _madx_variable_names(controllers::Vector{YAMLNode}, constants::Vector{String})
  claimed = Dict{String,Int}()
  for ele in controllers, (var, _) in _ctrl_variables(ele[1])
    claimed[var] = get(claimed, var, 0) + 1
  end
  taken = Set(_madx_definition_name(c) for c in constants)

  names    = Dict{Tuple{String,String},String}()
  initials = Dict{String,String}()
  for ele in controllers
    cname = node_key(ele[1])
    for (var, value) in _ctrl_variables(ele[1])
      madx = (claimed[var] > 1 || var in taken) ? "$(cname)__$(var)" : var
      names[(cname, var)] = madx
      initials[madx] = value
    end
  end
  return names, initials
end

#---------------------------------------------------------------------------------------------------
"""
    _check_madx_variables(lat::MadxLattice)

Report two MAD-X definitions that would claim the one name.

[`_madx_variable_names`](@ref) prefixes a controller variable that another controller's variable
or a constant already claims, which settles every collision a PALS lattice can have honestly.
This is the backstop for the one it cannot: a constant named after the prefixed form itself.
"""
function _check_madx_variables(lat::MadxLattice)
  seen = Dict{String,String}()
  for c in lat.constants
    seen[_madx_definition_name(c)] = "a constant or variable definition"
  end
  for ctrl in lat.controllers, var in ctrl.vars
    name = _madx_definition_name(var)
    haskey(seen, name) &&
        error("controller $(ctrl.name): variable `$name` is already defined by $(seen[name]); " *
              "MAD-X variables are global, so the two would drive one another")
    seen[name] = "controller $(ctrl.name)"
  end
  return nothing
end

#---------------------------------------------------------------------------------------------------
"""
    _madx_substitute(expr::AbstractString, replacements::Dict{String,String})

Return `expr` with each name in `replacements` replaced by what it maps to.

Used to put a controller's variables into an expression under whatever MAD-X calls them (see
[`_madx_variable_names`](@ref)), and to put their initial values in place of them. The match is
on whole identifiers, and a name reached through a dot is left alone, so a variable `cur` does
not rewrite `current` nor `SELF.cur`. Every name is replaced in one pass, so a replacement is
never itself replaced.
"""
function _madx_substitute(expr::AbstractString, replacements::Dict{String,String})
  isempty(replacements) && return String(expr)
  alternatives = join((replace(n, r"([\\^$.|?*+()\[\]{}])" => s"\\\1")
                       for n in keys(replacements)), "|")
  pattern = Regex("(?<![A-Za-z0-9_.])($alternatives)(?![A-Za-z0-9_])")
  return replace(String(expr), pattern => m -> replacements[m])
end

#---------------------------------------------------------------------------------------------------
"""
    _add_madx_branches!(lat::MadxLattice, branches)

Translate a PALS `Lattice`'s `branches` sequence into `lat`.

Append each branch to `lat.use` as a `name => periodic` pair. MAD-X has no geometry attribute
of its own: whether a branch closes on itself is decided by how it is used -- a `TWISS` given no
initial conditions looks for the periodic solution -- so the flag is carried through to the
comment [`write_madx_file`](@ref) writes beside the `use` statement.
"""
function _add_madx_branches!(lat::MadxLattice, branches)
  isempty(branches) && return lat
  for bl in branches
    if is_scalar(bl)
      name = String(bl)
      periodic = false
    elseif is_map(bl)
      bl_props = bl[1]
      name = node_key(bl_props)
      periodic = haskey(bl_props, "periodic") &&
                 lowercase(String(bl_props["periodic"])) == "true"
    elseif is_sequence(bl)
      error("Expanding lattices is not done during PALS>MAD-X translation")
    else
      error("This object is neither a scalar, map, nor sequence: ", bl)
    end
    push!(lat.use, name => periodic)
  end
  return lat
end

#---------------------------------------------------------------------------------------------------
"""
    write_madx_file(lat::MadxLattice, filename::String)

Serialize the [`MadxLattice`](@ref) `lat` to `filename` as a MAD-X lattice file.

Write the constant and variable definitions, the `BEAM` command and initial conditions, the
element definitions, the controller variables and their deferred assignments, the `line`
definitions, the `use` statement, and the `EALIGN` misalignments, each in its own labelled
section.

The order of the sections is the order MAD-X needs them in, which is stricter than Bmad's: a
name has to be defined above the point of use, `BEAM` has to come before `USE`, and the
`SELECT`/`EALIGN` pairs have to come after it, because there is no sequence to apply an error
to until one has been expanded.
"""
function write_madx_file(lat::MadxLattice, filename::String)
  open(filename, "w") do io
    n_section = 0
    # Head each section with the same rule and title, one blank line clear of the one before.
    function section(title)
      (n_section += 1) == 1 || write(io, "\n")
      write(io, "!======================================================================\n",
            "! $title \n\n")
    end

    if !isempty(lat.constants)
      section("Constant and variable definitions")
      for c in lat.constants
        write(io, c * ";\n")
      end
    end

    if !isempty(lat.beam) || !isempty(lat.beta0) || !isempty(lat.particle_start) || lat.rigidity
      section("Beam and initial conditions")
      isempty(lat.beam) || write(io, "beam, " * join(lat.beam, ", ") * ";\n")

      # A field the lattice states rather than normalizes is divided by this. MAD-X's own
      # `beam->brho` is P0/|q|, and the PALS normalization is by the signed charge.
      if lat.rigidity
        write(io, "\n! Signed magnetic rigidity P0/q, which normalizes a stated field.\n",
              "$_MADX_RIGIDITY := beam->brho * beam->charge / abs(beam->charge);\n")
      end

      if !isempty(lat.beta0)
        write(io, "\npals_beta0: beta0,\n\t" * join(lat.beta0, ",\n\t") * ";\n",
              "! twiss, beta0 = pals_beta0;\n")
      end

      # MAD-X starts a particle in the TRACK module, which has no place in a lattice file.
      if !isempty(lat.particle_start)
        write(io, "\n! Initial particle coordinates. MAD-X sets these with the START command:\n",
              "!   track;\n",
              "!   start, " * join(lat.particle_start, ", ") * ";\n",
              "!   run, turns = 1;\n",
              "!   endtrack;\n")
      end
    end

    section("Element definitions")
    for ele in lat.elements
      write(io, _format_madx_ele(ele) * "\n")
    end

    # A controller spans several lines, so the definitions are set apart from one another.
    if !isempty(lat.controllers)
      section("Controller definitions")
      write(io, join(_format_madx_controller.(lat.controllers), "\n\n") * "\n")
    end

    section("Beamline definitions")
    isempty(lat.beamlines) || write(io, join(_format_madx_line.(lat.beamlines), "\n\n") * "\n")

    section("Branch structure")
    for (i, (name, periodic)) in enumerate(lat.use)
      # MAD-X expands one sequence at a time, and each `use` replaces the last, so only the
      # first branch can be the active one.
      prefix = i == 1 ? "" : "! "
      geometry = periodic ? "closed" : "open"
      write(io, "$(prefix)use, period = $name;\t! $geometry\n")
    end
    length(lat.use) > 1 &&
        write(io, "! Only one branch can be expanded at a time; the rest are commented out.\n")

    # An EALIGN applies to whatever the preceding SELECT picked out of the expanded sequence,
    # so this section can only come after the `use` above.
    if !isempty(lat.alignments)
      section("Alignment errors")
      write(io, join(_format_madx_alignment.(lat.alignments), "\n\n") * "\n")
    end
  end
  return nothing
end

#---------------------------------------------------------------------------------------------------
"""
    _format_madx_ele(ele::MadxEleDef)

Render a [`MadxEleDef`](@ref) as a `name: type, attr = val, ...;` MAD-X element definition, with
each attribute on its own tab-indented continuation line and each note on a comment line above.
"""
function _format_madx_ele(ele::MadxEleDef)
  s = ""
  for note in ele.notes
    s *= "! $note\n"
  end
  s *= "$(ele.name): $(ele.type)"
  for a in ele.attrs
    s *= ",\n\t$a"
  end
  return s * ";"
end

#---------------------------------------------------------------------------------------------------
"""
    _format_madx_controller(ctrl::MadxController)

Render a [`MadxController`](@ref) as its variable definitions followed by the deferred
assignments that depend on them, under a comment naming the controller they came from.
"""
function _format_madx_controller(ctrl::MadxController)
  s = "! Controller $(ctrl.name)\n"
  for note in ctrl.notes
    s *= "! $note\n"
  end
  for var in ctrl.vars
    s *= "$var;\n"
  end
  return s * join([c * ";" for c in ctrl.controls], "\n")
end

#---------------------------------------------------------------------------------------------------
"""
    _format_madx_alignment(align::MadxAlignment)

Render a [`MadxAlignment`](@ref) as the `SELECT`/`EALIGN` pair that applies it.

The element is picked out by an anchored pattern rather than by a range so that a name which is
a prefix of another one does not take its neighbour's errors with it. A MAD-X label may hold a
decimal point, which a MAD-X pattern reads as "any character", so the name is escaped.
"""
function _format_madx_alignment(align::MadxAlignment)
  pattern = replace(align.name, r"([.*\[\]^$\\])" => s"\\\1")
  return "select, flag = error, clear;\n" *
         "select, flag = error, pattern = \"^$pattern\$\";\n" *
         "ealign, " * join(align.attrs, ", ") * ";"
end

#---------------------------------------------------------------------------------------------------
"""
    _format_madx_line(bl::MadxBeamline)

Render a [`MadxBeamline`](@ref) as a MAD-X `name: line = (...);` definition, wrapping the member
list with tab-indented continuation lines to keep rows under ~80 columns.
"""
function _format_madx_line(bl::MadxBeamline)
  line_str = ""
  tmp = ""
  l_tmp = length(bl.name) + 4
  n = length(bl.members)

  for (i, m) in enumerate(bl.members)
    ele_str = m
    i < n && (ele_str *= ", ")
    l_ele_str = length(ele_str)

    if l_tmp + l_ele_str < 80
      tmp *= ele_str
      l_tmp += l_ele_str
    else
      line_str *= tmp * "\n"
      tmp = "\t" * ele_str
      l_tmp = 7 + l_ele_str
    end
  end
  line_str *= tmp

  wrapped = (length(line_str) < 80) ? line_str : ("\n\t" * line_str * "\n\t")
  return "$(bl.name): line = ($wrapped);"
end

#---------------------------------------------------------------------------------------------------
"""
    _madx_scale(text::AbstractString, factor::Real)

Return `text` scaled by `factor`, as a MAD-X value.

PALS and MAD-X differ in the units of nearly every quantity that is not a length or an angle:
energies are eV against GeV, voltages V against MV, frequencies Hz against MHz. A value written
as a number is scaled here and comes out a number; one written as an expression -- a constant,
say -- is left for MAD-X to evaluate and comes out an expression.
"""
function _madx_scale(text::AbstractString, factor::Real)
  factor == 1 && return String(text)
  value = tryparse(Float64, strip(text))
  return value === nothing ? "($text) * $factor" : string(value * factor)
end

#---------------------------------------------------------------------------------------------------
"""
    _madx_shift(text::AbstractString, offset::Real)

Return `text` with `offset` added, as a MAD-X value. As with [`_madx_scale`](@ref), a number
comes out a number and an expression comes out an expression.
"""
function _madx_shift(text::AbstractString, offset::Real)
  offset == 0 && return String(text)
  value = tryparse(Float64, strip(text))
  return value === nothing ? "($text) + $offset" : string(value + offset)
end

#---------------------------------------------------------------------------------------------------
"""
    _madx_divide(text::AbstractString, divisor::AbstractString)

Return `text` divided by the MAD-X expression `divisor`, which is not a number here and so
cannot be worked out during translation.
"""
_madx_divide(text::AbstractString, divisor::AbstractString) = "($text) / $divisor"

#---------------------------------------------------------------------------------------------------
"""
    _madx_strength(value::Real, normalized::Bool)

Return a magnet strength as a MAD-X value.

Every MAD-X strength attribute is normalized, so a PALS component given as a field is divided by
the reference rigidity (see [`_MADX_RIGIDITY`](@ref)) instead of being written out as it stands.
"""
_madx_strength(value::Real, normalized::Bool) =
    normalized ? string(value) : "$value / $_MADX_RIGIDITY"

#---------------------------------------------------------------------------------------------------
"""
    _madx_logical(node::YAMLNode)

Return a PALS boolean as MAD-X's `true`/`false`.
"""
_madx_logical(node::YAMLNode) = lowercase(String(node)) == "true" ? "true" : "false"

#---------------------------------------------------------------------------------------------------
"""
    _madx_check_name(name::String)

Report a name MAD-X cannot hold, and warn about one it would quietly truncate.

A MAD-X label is at most sixteen characters -- the rest are dropped, which can turn two elements
into one -- and may not be one of MAD-X's own keywords, which is a fatal error there.
"""
function _madx_check_name(name::String)
  lowercase(name) in _MADX_KEYWORDS &&
      error("$name: is a MAD-X keyword and cannot be used as a label")
  length(name) > 16 &&
      println("$name: is longer than the 16 characters a MAD-X label keeps; " *
              "the rest will be dropped")
  return name
end

#---------------------------------------------------------------------------------------------------
"""
    _madx_check_expression(where::String, text::AbstractString)

Report a PALS expression MAD-X has no way to evaluate, and return `text` unchanged.

An expression is carried across as it stands, MAD-X's arithmetic and its ordinary functions
being PALS' as well. Two things in one are not: PALS' particle-data functions, which look up a
species in a table MAD-X does not carry, and most of PALS' predefined constants, which MAD-X
either spells differently or does not have. Both are reported rather than rewritten -- as they
are for the other translators, expression translation being an open item for all of them.
"""
function _madx_check_expression(where::String, text::AbstractString)
  for fn in ("mass_of", "charge_of", "anomalous_moment_of")
    occursin("$fn(", text) &&
        println("$where: `$fn` is a PALS function with no MAD-X equivalent; " *
                "`$text` will not evaluate")
  end
  for name in keys(_MADX_CONSTANT_NAMES)
    occursin(Regex("(?<![A-Za-z0-9_])$name(?![A-Za-z0-9_])"), text) || continue
    madx = _MADX_CONSTANT_NAMES[name]
    println("$where: the PALS constant `$name` is " *
            (madx === nothing ? "not one MAD-X has" : "MAD-X's `$madx`") *
            "; `$text` needs it renamed by hand")
  end
  return text
end

#---------------------------------------------------------------------------------------------------
"""
    _MADX_CONSTANT_NAMES

The PALS predefined constants MAD-X either spells differently or does not have at all.

`pi` is the one the two agree on and is absent from this list. A value of `nothing` means MAD-X
has no constant for it. MAD-X's `emass`, `pmass` and `mumass` are masses in GeV, where PALS'
`mass_of` is in eV, so they are not a rename of anything here.
"""
const _MADX_CONSTANT_NAMES =
    Dict("c_light"    => "clight",  "e_charge"               => "qelect",
         "r_electron" => "erad",    "r_proton"               => "prad",
         "h_planck"   => nothing,   "hbar"                   => nothing,
         "k_boltzmann" => nothing,  "eps_0_vac"              => nothing,
         "mu_0_vac"   => "amu0",    "classical_radius_factor" => nothing,
         "fine_structure" => nothing, "n_avogadro"           => nothing)

#---------------------------------------------------------------------------------------------------
"""
    _madx_constants(node::YAMLNode)

Translate a compact-form `constants:`/`variables:` list into MAD-X `name = value` definitions.

MAD-X draws no distinction between the two: both become a named value the rest of the lattice
file may use in an expression, so both lists translate the same way.
"""
_madx_constants(node::YAMLNode) =
    ["$name = $(_madx_check_expression(name, value))" for (name, value) in _name_value_pairs(node)]

#---------------------------------------------------------------------------------------------------
"""
    _madx_constant(props::YAMLNode, pals_kind::String)

Translate a full-form (`kind: constant`, `kind: variable`) definition into a MAD-X
`name = value` definition.

A definition whose `value` is a structure rather than a single value has no MAD-X equivalent and
raises an error; one with no `value` at all takes PALS' default of zero. A MAD-X variable is a
value and nothing else, so the error bars a PALS definition may carry are reported.
"""
function _madx_constant(props::YAMLNode, pals_kind::String)
  name = node_key(props)
  for err in ("absolute_error", "relative_error")
    haskey(props, err) &&
        println("$name: a MAD-X variable carries no error bar, so $err is not translated")
  end
  haskey(props, "value") || return "$name = 0"
  value = props["value"]
  (is_map(value) || is_sequence(value)) &&
      error("$name: the `value` of a `$pals_kind` is not a single value")
  return "$name = $(_madx_check_expression(name, _value_text(value)))"
end

#---------------------------------------------------------------------------------------------------
"""
    _madx_species(species::String)

Map a PALS reference species onto a MAD-X `PARTICLE`.

MAD-X knows the mass and charge of a fixed handful of species and nothing else; anything outside
that set has to be given its mass and charge outright, which PALS does not state and which the
translation therefore cannot supply.
"""
function _madx_species(species::String)
  known = Dict("positron" => "positron", "electron" => "electron", "proton" => "proton",
               "anti-proton" => "antiproton", "antiproton" => "antiproton",
               "muon+" => "posmuon", "posmuon" => "posmuon",
               "muon-" => "negmuon", "negmuon" => "negmuon", "muon" => "negmuon")
  name = lowercase(strip(species, ['"', '\'', ' ']))
  haskey(known, name) && return known[name]
  println("species_ref `$species` is not one MAD-X knows; its mass and charge have to be " *
          "given to the BEAM command by hand")
  return name
end

#---------------------------------------------------------------------------------------------------
"""
    _ele_to_madx_str(ele::YAMLNode)

Translate a `BeginningEle` element into the MAD-X beam and initial-condition settings.

Return `(beam, beta0, particle)` where `beam` holds the `BEAM` attributes from the element's
`ReferenceP` (species and energy), `beta0` holds the `BETA0` attributes from its `TwissP`
(initial Twiss and dispersion), and `particle` holds the `START` attributes from its `ParticleP`
(initial phase-space coordinates).

Three PALS quantities do not survive the crossing:
  - PALS states the Twiss parameters in the `a`/`b` normal modes and MAD-X in the `x`/`y`
    planes, which are the same thing only when the lattice is uncoupled.
  - The coupling itself is stated as Bmad's `C` matrix here and as MAD-X's `R` matrix there,
    which are different parametrizations, so `cmat11` and its fellows are not translated.
  - MAD-X has no dispersion derivative, only the momentum dispersion, so `deta_x_ds` is not
    translated either.
"""
function _ele_to_madx_str(ele::YAMLNode)
  props = ele[1]
  name = node_key(props)
  beam = String[]
  beta0 = String[]
  particle = String[]
  for key in keys(props)
    if key == "TwissP"
      twissP = props["TwissP"]
      for k in keys(twissP)
        val = String(twissP[k])
        if k == "beta_a"
          push!(beta0, "betx = $val")
        elseif k == "beta_b"
          push!(beta0, "bety = $val")
        elseif k == "alpha_a"
          push!(beta0, "alfx = $val")
        elseif k == "alpha_b"
          push!(beta0, "alfy = $val")
        # MAD-X counts the phase in turns where PALS counts it in radians.
        elseif k == "phi_a"
          push!(beta0, "mux = $(_madx_scale(val, 1 / 2π))")
        elseif k == "phi_b"
          push!(beta0, "muy = $(_madx_scale(val, 1 / 2π))")
        # MAD-X differentiates against `pt` and PALS against `pz`, and `pt = beta * pz`.
        elseif k == "eta_x"
          push!(beta0, "dx = $(_madx_divide(val, _MADX_BETA))")
        elseif k == "eta_y"
          push!(beta0, "dy = $(_madx_divide(val, _MADX_BETA))")
        elseif k == "etap_x"
          push!(beta0, "dpx = $(_madx_divide(val, _MADX_BETA))")
        elseif k == "etap_y"
          push!(beta0, "dpy = $(_madx_divide(val, _MADX_BETA))")
        elseif startswith(k, "cmat")
          println("$name: TwissP.$k is Bmad's coupling matrix, which is not MAD-X's R matrix, " *
                  "not translated")
        elseif k == "deta_x_ds" || k == "deta_y_ds"
          println("$name: TwissP.$k has no MAD-X equivalent, not translated")
        end
      end
    elseif key == "ReferenceP"
      referenceP = props["ReferenceP"]
      for k in keys(referenceP)
        val = String(referenceP[k])
        if k == "species_ref"
          push!(beam, "particle = $(_madx_species(val))")
        # PALS states the reference energy in eV, MAD-X in GeV.
        elseif k == "pc_ref"
          push!(beam, "pc = $(_madx_scale(val, 1e-9))")
        elseif k == "E_tot_ref"
          push!(beam, "energy = $(_madx_scale(val, 1e-9))")
        elseif k == "time_ref" || k == "location"
          println("$name: ReferenceP.$k has no MAD-X equivalent, not translated")
        end
      end
    elseif key == "ParticleP"
      particleP = props["ParticleP"]
      for k in keys(particleP)
        val = String(particleP[k])
        if k in ("x", "px", "y", "py")
          push!(particle, "$k = $val")
        # MAD-X's longitudinal pair is measured against the energy where PALS' is measured
        # against the momentum, and the two differ by the reference velocity.
        elseif k == "z"
          push!(particle, "t = $(_madx_divide(val, _MADX_BETA))")
        elseif k == "pz"
          push!(particle, "pt = $val * $_MADX_BETA")
        elseif k == "spin_x" || k == "spin_y" || k == "spin_z"
          println("$name: ParticleP.$k has no MAD-X equivalent, not translated")
        end
      end
    end
  end
  # MAD-X takes the species first and works the rest of the beam out from it, so that is the
  # order the BEAM command reads best in whatever order the PALS file gave.
  sort!(beam, by = s -> startswith(s, "particle") ? 0 : 1, alg = MergeSort)
  return beam, beta0, particle
end

#---------------------------------------------------------------------------------------------------
"""
    _make_madx_line(ele::YAMLNode, facility::YAMLNode)

Translate a `BeamLine` element into a [`MadxBeamline`](@ref).

Collect the member element names into the returned beamline. A leading `BeginningEle` is dropped
-- it carries the reference parameters, which become the `BEAM` command, and MAD-X has no
element for it -- whether it is spelled out in the line or named there and defined in the
`facility`. A line that does not begin with one, which is a branch forked into with its
reference parameters propagated, keeps every element it has.
"""
function _make_madx_line(ele::YAMLNode, facility::YAMLNode)
  props = ele[1]
  name = _madx_check_name(node_key(props))
  line = props["line"]

  members = String[]
  for i in 1:length(line)
    line_ele = line[i]
    if is_scalar(line_ele)
      member = String(line_ele)
    elseif is_map(line_ele) || is_sequence(line_ele)
      member = node_key(line_ele[1])
    else
      error("BeamLine $name element $i is not scalar or sequence or map")
    end

    if i == 1
      entry_props = (is_map(line_ele) || is_sequence(line_ele)) ? line_ele[1] :
                    _facility_props(facility, member)
      entry_props !== nothing && haskey(entry_props, "kind") &&
          String(entry_props["kind"]) == "BeginningEle" && continue
    end
    push!(members, member)
  end
  return MadxBeamline(name, members)
end

#---------------------------------------------------------------------------------------------------
"""
    _madx_kind(ele_kind::String)

Map a PALS element kind to its MAD-X counterpart.

Return the MAD-X element-type keyword for the PALS `ele_kind`. Kinds with no MAD-X equivalent
raise an error: MAD-X has no branching (`Fork`), no support structures (`Girder`), no element
that changes the reference energy in mid-line (`ReferenceChange`), and no way to build one
element out of several (`UnionEle`).
"""
function _madx_kind(ele_kind::String)
  # Magnets and RF Cavities
  if      ele_kind == "ACKicker";         return error("No MAD-X equivalent of an ACKicker: " *
                                                       "HACDIPOLE and VACDIPOLE each act in one plane")
  # PALS has the one `Bend`, whose reference geometry is a sector; the pole face rotations
  # that make a bend rectangular are parameters of it (`e1_rect`, `e2_rect`), not a second
  # kind. MAD-X splits the two, so `Bend` maps to MAD-X's sector bend and MAD-X's `RBEND` has
  # no PALS kind to map from.
  elseif  ele_kind == "Bend";             return "sbend"
  elseif  ele_kind == "CrabCavity";       return "crabcavity"
  elseif  ele_kind == "Drift";            return "drift"
  elseif  ele_kind == "Kicker";           return "kicker"
  elseif  ele_kind == "Multipole";        return "multipole"
  elseif  ele_kind == "Octupole";         return "octupole"
  elseif  ele_kind == "Quadrupole";       return "quadrupole"
  elseif  ele_kind == "RFCavity";         return "rfcavity"
  elseif  ele_kind == "Sextupole";        return "sextupole"
  elseif  ele_kind == "Solenoid";         return "solenoid"
  elseif  ele_kind == "Wiggler";          return error("No Wiggler elements in MAD-X")

  # Beam and Plasma Elements
  elseif  ele_kind == "BeamBeam";         return "beambeam"

  # Sources and Collimation
  elseif  ele_kind == "Converter";        return error("No Converter elements in MAD-X")
  elseif  ele_kind == "EGun";             return error("No EGun elements in MAD-X")
  elseif  ele_kind == "Foil";             return error("No Foil elements in MAD-X")
  # A MAD-X collimator is a drift that its aperture can stop a particle in, which is what a
  # PALS Mask is; MAD-X has nothing for the mask pattern itself.
  elseif  ele_kind == "Mask";             return "collimator"

  # Instrumentation and Diagnostics
  elseif  ele_kind == "Instrument";       return "instrument"

  # Map Elements
  elseif  ele_kind == "Match";            return error("No Match elements in MAD-X")
  elseif  ele_kind == "Taylor";           return "matrix"

  # Bookkeeping Elements
  # MAD-X has no beginning element: the reference parameters a PALS BeginningEle carries are
  # the BEAM command, and are handled before this point.
  elseif  ele_kind == "BeginningEle";     return "marker"
  elseif  ele_kind == "Fiducial";         return error("No Fiducial elements in MAD-X")
  elseif  ele_kind == "FloorShift";       return error("No FloorShift elements in MAD-X")
  elseif  ele_kind == "Fork";             return error("No Fork elements in MAD-X: a MAD-X " *
                                                       "lattice does not branch")
  elseif  ele_kind == "Marker";           return "marker"
  elseif  ele_kind == "Placeholder";      return "placeholder"
  elseif  ele_kind == "Patch";            return "changeref"
  elseif  ele_kind == "ReferenceChange";  return error("No ReferenceChange elements in MAD-X: " *
                                                       "the reference energy is the BEAM command's")

  # Structural and Grouping Elements
  elseif  ele_kind == "Girder";           return error("No Girder elements in MAD-X")
  elseif  ele_kind == "UnionEle";         return error("No UnionEle in MAD-X")

  # External Circuits
  elseif  ele_kind == "Feedback";         return error("No Feedback elements in MAD-X")

  else
    error("Element kind $ele_kind is not translated to MAD-X")
  end
end

#---------------------------------------------------------------------------------------------------
"""
    _MADX_NATIVE_STRENGTH

The multipole orders an element kind holds as its own strength, and the MAD-X attributes that
hold them.

Each entry maps a PALS element kind to a map from `(order, skew)` to the MAD-X attribute name.
A quadrupole's order-1 field is MAD-X's `k1`, not a multipole of a general element; a bend also
carries a quadrupole and a sextupole component of its own. Every attribute here holds a
strength that is not length integrated, bar the kicker's, which holds a deflection angle -- see
[`_madx_native_strength!`](@ref).

MAD-X's normal and skew coefficients are the plain field derivatives, `Kn L = (L/Brho) d^n
By/dx^n` and `Ks n L = (L/Brho) d^n Bx/dx^n`, and so are PALS': the `1/N!` of the PALS field
expansion belongs to the expansion and not to the coefficient. So, unlike the Bmad translation,
nothing here picks up a factorial.
"""
const _MADX_NATIVE_STRENGTH =
    Dict("Bend"       => Dict((0, false) => "angle", (1, false) => "k1",
                              (1, true) => "k1s", (2, false) => "k2"),
         "Quadrupole" => Dict((1, false) => "k1", (1, true) => "k1s"),
         "Sextupole"  => Dict((2, false) => "k2", (2, true) => "k2s"),
         "Octupole"   => Dict((3, false) => "k3", (3, true) => "k3s"),
         "Kicker"     => Dict((0, false) => "hkick", (0, true) => "vkick"))

#---------------------------------------------------------------------------------------------------
"""
    _MADX_INTEGRATED_STRENGTH

The MAD-X strength attributes that hold a length-integrated value.

Every other attribute in [`_MADX_NATIVE_STRENGTH`](@ref) holds a strength per unit length, so a
PALS value has to be integrated or de-integrated to match whichever it lands in.
"""
const _MADX_INTEGRATED_STRENGTH = Set(["angle", "hkick", "vkick"])

#---------------------------------------------------------------------------------------------------
"""
    _MADX_THIN_KINDS

The MAD-X element types that have no length attribute at all.

MAD-X rejects an attribute an element type does not have, so a `length` -- which every PALS
element may carry, if only as a zero -- cannot simply be written out. A `multipole` is thin too
but does have a length of a sort, the fictitious `lrad`, and is handled apart from these.
"""
const _MADX_THIN_KINDS = Set(["marker", "beambeam", "changeref"])

#---------------------------------------------------------------------------------------------------
"""
    _madx_multipole(full::FullRepresentation, order::Int)

Return the normal and skew components of multipole `order`, with the multipole's own tilt
rotated into them.

A tilt of `T` on an order-`N` multipole rotates it by `(N+1) T` in the normal/skew plane. MAD-X
has one tilt for the whole element rather than one per order, so the rotation is worked out here
and what comes out is a plain normal/skew pair. The components keep whatever units the PALS
file gave them: normalized or not, integrated or not.
"""
function _madx_multipole(full::FullRepresentation, order::Int)
  value = first([1 1im] * full.magnitude[order]) * _tilt_rotation(order, get(full.tilt, order, 0.0))
  return real(value), imag(value)
end

#---------------------------------------------------------------------------------------------------
"""
    _madx_native_strength!(full::FullRepresentation, ele_kind::String, name::String, ref_angle)

Take the multipoles that are an element's own strength out of `full` and return their MAD-X
attribute fragments.

The strength of a MAD-X quadrupole is its `k1`, so that is where a PALS `Kn1` belongs. Unlike
Bmad, MAD-X has an attribute for the skew component of each of these -- `k1s`, `k2s`, `k3s` --
so a tilted multipole of the element's own order needs nothing left over, and unlike Bmad it has
no field-valued attribute, so an unnormalized component is divided by the reference rigidity.

The length is put in or taken out to match the attribute: `k1` is a strength per unit length and
`angle` and the kicker's `hkick` are integrated. An element of zero length whose PALS value is
not integrated has no strength to state, and neither has one whose integrated value cannot be
spread over a length of zero; both are reported.

Two of these attributes are not simply the multipole they come from:
  - A bend's order-0 field is its `angle`. Bmad states the departure of the field from the
    reference bend and can hold the two apart; MAD-X cannot, because it builds the bend's
    geometry out of the same `angle` it tracks through (`k0` is in its database but not in its
    map). So `ref_angle`, the angle the `BendP` geometry has already been written out as (see
    [`_madx_bend_angle`](@ref)), is what the field is checked against: a `Kn0` that agrees with
    it has nothing left to state, and one that disagrees is reported and dropped, because the
    alternative -- writing the field out as the angle -- would move every element downstream
    of the bend.
  - A kicker's deflection is measured the opposite way round from a bend's, in both MAD-X and
    PALS: a positive `hkick` bends towards positive `x` and a positive `Kn0` towards negative
    `x`, so the horizontal one changes sign.
"""
function _madx_native_strength!(full::FullRepresentation, ele_kind::String, name::String,
                                ref_angle = nothing)
  attrs = String[]
  haskey(_MADX_NATIVE_STRENGTH, ele_kind) || return attrs
  native = _MADX_NATIVE_STRENGTH[ele_kind]

  for order in sort(collect(keys(full.magnitude)))
    haskey(native, (order, false)) || haskey(native, (order, true)) || continue
    normal, skew = _madx_multipole(full, order)
    normalized = full.normalized[order]

    for (component, is_skew) in ((normal, false), (skew, true))
      attribute = get(native, (order, is_skew), nothing)
      if attribute === nothing
        component ≈ 0 ||
            println("$name: a MAD-X $(_madx_kind(ele_kind)) has no attribute for the " *
                    "$(is_skew ? "skew" : "normal") order-$order multipole, not translated")
        continue
      end

      # Put the length in, or take it out, to match what the attribute holds.
      integrated = attribute in _MADX_INTEGRATED_STRENGTH
      value = component
      if integrated && !full.integrated[order]
        value *= full.L
      elseif !integrated && full.integrated[order]
        if full.L == 0
          value ≈ 0 ||
              println("$name: an integrated order-$order multipole cannot be spread over an " *
                      "element of zero length, not translated")
          continue
        end
        value /= full.L
      end
      attribute == "hkick" && (value = -value)

      # The bend's geometry has already been written out as this same attribute.
      if attribute == "angle" && ref_angle !== nothing
        ref_text, ref_value = ref_angle
        # A bend given only a skew order-0 states no field angle to reconcile at all.
        (value ≈ 0 && full.magnitude[order][1] ≈ 0) && continue
        normalized && ref_value !== nothing && value ≈ ref_value && continue
        println("$name: the bend field states an angle of $(_madx_strength(value, normalized)) " *
                "where the reference bend geometry states $ref_text; MAD-X has the one `angle` " *
                "for both, so the field is not translated")
        continue
      end

      value ≈ 0 && continue
      push!(attrs, "$attribute = $(_madx_strength(value, normalized))")
    end

    # Whichever components landed somewhere are the element's own and stay out of the
    # multipole form; the rest were reported just above.
    delete!(full.magnitude, order)
    delete!(full.integrated, order)
    delete!(full.normalized, order)
    delete!(full.tilt, order)
  end
  return attrs
end

#---------------------------------------------------------------------------------------------------
"""
    _madx_multipole_attrs(full::FullRepresentation, name::String)

Return the `knl`/`ksl` attribute fragments of a MAD-X `multipole`.

MAD-X states a thin multipole as two arrays of integrated coefficients indexed by order from
zero up, so an order that is not there still needs its zero written in. A component given as a
field is divided by the reference rigidity, which makes the array entry an expression rather
than a number -- which MAD-X is happy with, the entries being expressions in general.
"""
function _madx_multipole_attrs(full::FullRepresentation, name::String)
  isempty(full.magnitude) && return String[]
  n = maximum(keys(full.magnitude))
  knl = fill("0", n + 1)
  ksl = fill("0", n + 1)
  has_normal = false
  has_skew = false

  for order in keys(full.magnitude)
    normal, skew = _madx_multipole(full, order)
    # Every entry of a MAD-X multipole array is length integrated.
    if !full.integrated[order]
      normal *= full.L
      skew   *= full.L
    end
    normalized = full.normalized[order]
    if !(normal ≈ 0)
      knl[order + 1] = _madx_strength(normal, normalized)
      has_normal = true
    end
    if !(skew ≈ 0)
      ksl[order + 1] = _madx_strength(skew, normalized)
      has_skew = true
    end
  end

  attrs = String[]
  has_normal && push!(attrs, "knl = {" * join(knl, ", ") * "}")
  has_skew   && push!(attrs, "ksl = {" * join(ksl, ", ") * "}")
  return attrs
end

#---------------------------------------------------------------------------------------------------
"""
    _madx_fold(text::AbstractString, f, args::AbstractString...)

Return `text`, or the number it comes to when every one of `args` is a number.

A PALS parameter may be written as an expression, which only MAD-X can evaluate, or as a plain
number, which the translation can work with. Where a MAD-X value has to be derived from several
PALS ones, `text` is that derivation written as a MAD-X expression and `f` is the same
derivation as a function, applied here when all of its inputs parse.
"""
function _madx_fold(text::AbstractString, f, args::AbstractString...)
  values = [tryparse(Float64, strip(a)) for a in args]
  any(isnothing, values) && return String(text)
  result = f(values...)
  return isfinite(result) ? string(result) : String(text)
end

#---------------------------------------------------------------------------------------------------
"""
    _madx_times(a::AbstractString, b::AbstractString)

Return the product of two MAD-X values, without the clutter of a factor of one.

Two numbers are multiplied out here; a unit factor -- which is what an element of unit length
gives, and what several of the bend derivations reduce to -- comes back as the other operand
alone rather than as a product with nothing in it.
"""
function _madx_times(a::AbstractString, b::AbstractString)
  va, vb = tryparse(Float64, strip(a)), tryparse(Float64, strip(b))
  va !== nothing && vb !== nothing && return string(va * vb)
  va == 1 && return String(b)
  vb == 1 && return String(a)
  return "($a) * ($b)"
end

#---------------------------------------------------------------------------------------------------
"""
    _madx_bend_geometry(props::YAMLNode, name::String)

Return the reference geometry of a `Bend` as `(angle, angle_value, arc_length)`, or `nothing`
if the element states none.

PALS states a bend's geometry with any two of three sets of mutually dependent parameters --
a curvature (`g_ref`, `radius_ref` or the reference field `Bn0_ref`), a length (`length`,
`L_chord` or `L_rectangle`), and the angle (`angle_ref`) -- one parameter from each of two
different sets, from which every other parameter follows. MAD-X states it with exactly two, the
`angle` and the arc length `l`, so whichever pair the PALS file used has to be turned into that
pair here.

Only the field-valued curvature needs the reference rigidity, the others being pure geometry.
`angle_value` is the angle as a number when everything it was derived from is one, and `nothing`
when it is an expression only MAD-X can evaluate. A bend that states too little for the pair to
be worked out is reported, and comes back with whichever of the two is known.
"""
function _madx_bend_geometry(props::YAMLNode, name::String)
  haskey(props, "BendP") || return nothing
  bendP = props["BendP"]

  # The curvature, however the PALS file chose to state it.
  g = haskey(bendP, "g_ref")      ? String(bendP["g_ref"]) :
      haskey(bendP, "radius_ref") ? _madx_fold("1 / ($(String(bendP["radius_ref"])))",
                                               r -> 1 / r, String(bendP["radius_ref"])) :
      haskey(bendP, "Bn0_ref")    ? "$(String(bendP["Bn0_ref"])) / $_MADX_RIGIDITY" : nothing

  # A length, and which of the three lengths it is: MAD-X wants the arc.
  len_kind, len =
      haskey(props, "length")        ? (:arc,   String(props["length"])) :
      haskey(bendP, "L_chord")       ? (:chord, String(bendP["L_chord"])) :
      haskey(bendP, "L_rectangle")   ? (:rect,  String(bendP["L_rectangle"])) : (:none, nothing)

  angle = haskey(bendP, "angle_ref") ? String(bendP["angle_ref"]) : nothing
  arc   = len_kind == :arc ? len : nothing

  # The angle and the arc length, from whichever pair of the three sets was given.
  if angle === nothing && g !== nothing && len !== nothing
    if len_kind == :arc
      angle = _madx_times(g, len)
    elseif len_kind == :chord
      angle = _madx_fold("2 * asin(($g) * ($len) / 2)", (a, b) -> 2asin(a * b / 2), g, len)
    else
      angle = _madx_fold("asin(($g) * ($len))", (a, b) -> asin(a * b), g, len)
    end
  end

  if arc === nothing && angle !== nothing
    if len_kind == :chord
      arc = _madx_fold("($angle) * ($len) / (2 * sin(($angle) / 2))",
                       (a, l) -> a * l / (2sin(a / 2)), angle, len)
    elseif len_kind == :rect
      arc = _madx_fold("($angle) * ($len) / sin($angle)", (a, l) -> a * l / sin(a), angle, len)
    elseif g !== nothing
      arc = _madx_fold("($angle) / ($g)", (a, b) -> a / b, angle, g)
    end
  end

  if angle === nothing && arc === nothing
    return nothing
  elseif angle === nothing || arc === nothing
    println("$name: BendP states too little of the bend geometry for MAD-X, which needs both " *
            "the angle and the arc length")
  end
  return angle, (angle === nothing ? nothing : tryparse(Float64, strip(angle))), arc
end

#---------------------------------------------------------------------------------------------------
"""
    _madx_bend_faces(bendP::YAMLNode, name::String, angle)

Return the `e1`/`e2` attribute fragments of a bend's pole faces.

MAD-X measures the pole-face rotations of an `sbend` against the sector geometry, which is what
PALS' own `e1` and `e2` are measured against, so those two come straight across. PALS also has
`e1_rect` and `e2_rect`, measured against fiducial lines parallel to each other, and what
separates the two pairs depends on the bend's `ref_geometry`:

    ARC, CHORD        e1 = e1_rect + angle/2,   e2 = e2_rect + angle/2
    ENTRANCE_COORDS   e1 = e1_rect,             e2 = e2_rect + angle
    EXIT_COORDS       e1 = e1_rect + angle,     e2 = e2_rect

A face given both ways is contradictory and raises an error; one given the rectangular way on a
bend whose angle is unknown cannot be converted, and raises one too.
"""
function _madx_bend_faces(bendP::YAMLNode, name::String, angle)
  attrs = String[]
  geometry = haskey(bendP, "ref_geometry") ? String(bendP["ref_geometry"]) : "ARC"

  for (face, rect, share) in (("e1", "e1_rect", geometry == "ENTRANCE_COORDS" ? 0.0 :
                                                geometry == "EXIT_COORDS"     ? 1.0 : 0.5),
                              ("e2", "e2_rect", geometry == "ENTRANCE_COORDS" ? 1.0 :
                                                geometry == "EXIT_COORDS"     ? 0.0 : 0.5))
    has_face, has_rect = haskey(bendP, face), haskey(bendP, rect)
    has_face && has_rect &&
        error("$name: should not have both $face and $rect")
    if has_face
      push!(attrs, "$face = $(String(bendP[face]))")
    elseif has_rect
      angle === nothing &&
          error("$name: $rect is measured against the bend angle, which is not given")
      share == 0 && (push!(attrs, "$face = $(String(bendP[rect]))"); continue)
      push!(attrs, "$face = " * _madx_fold("$(String(bendP[rect])) + $share * ($angle)",
                                           (r, a) -> r + share * a, String(bendP[rect]), angle))
    end
  end
  return attrs
end

#---------------------------------------------------------------------------------------------------
"""
    _madx_aperture_attrs(apertureP::YAMLNode, name::String, madx_kind::String)

Return the `apertype`/`aperture`/`aper_offset` attribute fragments of a PALS `ApertureP`.

MAD-X states an aperture as a half width and a half height about the element's axis, with the
offset of the aperture's centre given separately; PALS states the two edges, or a full width and
a centre. Both forms come to the same half-extent and centre, which is what is written out.

The `shape` decides which of the components describe the aperture: a `RECTANGULAR` or
`ELLIPTICAL` one is bounded by its limits and ignores any vertices, and a `VERTICES` one is
bounded by its vertex list and ignores any limits. MAD-X can only take a vertex outline from a
file of its own, so a `VERTICES` aperture is reported rather than written out.

Shape, location and the rest describe an aperture; they do not put one there. Writing them out
for a group that sets no limit would hand MAD-X an aperture the PALS lattice does not have, so a
group that bounds nothing is skipped entirely. A group that bounds one plane and not the other
still has to state both, MAD-X's aperture values being positional; the unbounded plane is left
wide open and reported.

What MAD-X has no room for is reported: it puts an aperture at the entrance of an element and
nowhere else, so `location` is lost, and it has no aperture at all on a drift.
"""
function _madx_aperture_attrs(apertureP::YAMLNode, name::String, madx_kind::String)
  attrs = String[]
  shape = haskey(apertureP, "shape") ? String(apertureP["shape"]) : "ELLIPTICAL"

  if shape == "VERTICES"
    println("$name: MAD-X takes a vertex outline from a file of its own, which PALS does not " *
            "name, so a VERTICES aperture is not translated")
    return attrs
  elseif shape == "CUSTOM_SHAPE"
    println("$name: a CUSTOM_SHAPE aperture is defined outside PALS and has no MAD-X " *
            "equivalent, not translated")
    return attrs
  end

  has_xmin   = haskey(apertureP, "x_min");    has_xmax  = haskey(apertureP, "x_max")
  has_xwidth = haskey(apertureP, "x_width");  has_xcen  = haskey(apertureP, "x_center")
  has_ymin   = haskey(apertureP, "y_min");    has_ymax  = haskey(apertureP, "y_max")
  has_ywidth = haskey(apertureP, "y_width");  has_ycen  = haskey(apertureP, "y_center")

  # A RECTANGULAR or ELLIPTICAL aperture is bounded by its limits alone, so a group that sets
  # none of them bounds nothing, whatever else it says.
  has_xmin || has_xmax || has_xwidth || has_xcen ||
      has_ymin || has_ymax || has_ywidth || has_ycen || return attrs

  if madx_kind == "drift"
    println("$name: MAD-X cannot put an aperture on a drift; use a collimator, not translated")
    return attrs
  end

  # `_half_and_centre` returns the half extent and the centre of one plane, which is what MAD-X
  # wants, from whichever of the two PALS forms the group used.
  function _half_and_centre(plane, has_min, has_max, has_width, has_centre)
    if (has_min || has_max) && (has_width || has_centre)
      println("
                Ignoring the $plane aperture of element $name.
                Either $(plane)_min and max should be defined or width and center, not both.
                ")
      return nothing
    elseif has_width
      width  = Float64(apertureP["$(plane)_width"])
      centre = has_centre ? Float64(apertureP["$(plane)_center"]) : 0.0
      return width / 2, centre
    elseif has_min && has_max
      lo = Float64(apertureP["$(plane)_min"])
      hi = Float64(apertureP["$(plane)_max"])
      return (hi - lo) / 2, (hi + lo) / 2
    elseif has_min || has_max
      println("$name: only one side of the $plane aperture is set, which MAD-X cannot state")
      return nothing
    end
    return nothing
  end

  x = _half_and_centre("x", has_xmin, has_xmax, has_xwidth, has_xcen)
  y = _half_and_centre("y", has_ymin, has_ymax, has_ywidth, has_ycen)
  if x === nothing && y === nothing
    println("$name: ApertureP sets no limit MAD-X can state, not translated")
  else
    # MAD-X's aperture values are positional, so a plane that is not bounded still has to be
    # given a value; one metre is well outside anything an accelerator aperture bounds.
    if x === nothing || y === nothing
      println("$name: MAD-X states both aperture planes together; the unbounded one is " *
              "written out as 1 m")
    end
    x_half, x_centre = x === nothing ? (1.0, 0.0) : x
    y_half, y_centre = y === nothing ? (1.0, 0.0) : y
    push!(attrs, "aperture = {$x_half, $y_half}")
    (x_centre ≈ 0 && y_centre ≈ 0) ||
        push!(attrs, "aper_offset = {$x_centre, $y_centre}")
  end

  for akey in keys(apertureP)
    if akey == "shape"
      shape = String(apertureP["shape"])
      if shape == "ELLIPTICAL"
        push!(attrs, "apertype = ellipse")
      elseif shape == "RECTANGULAR"
        push!(attrs, "apertype = rectangle")
      else
        error("$name: aperture shape $shape is not supported")
      end
    elseif akey == "location"
      println("$name: MAD-X checks an aperture at the entrance of an element only, so " *
              "ApertureP.location is not translated")
    elseif akey == "aperture_active"
      lowercase(String(apertureP["aperture_active"])) == "false" &&
          println("$name: MAD-X cannot switch an aperture off; remove it instead")
    # A RECTANGULAR or ELLIPTICAL aperture ignores any vertices, so there is nothing to say
    # about them here.
    elseif akey in ("aperture_shifts_with_body", "material", "thickness")
      println("$name: ApertureP.$akey has no MAD-X equivalent, not translated")
    end
  end
  return attrs
end

#---------------------------------------------------------------------------------------------------
"""
    _make_madx_ele(ele::YAMLNode)

Translate a single PALS element into a [`MadxEleDef`](@ref) and its [`MadxAlignment`](@ref).

Dispatch on the element `kind` and its parameter groups (aperture, bend, body shift, multipoles,
patch, RF, solenoid, ...) to build the MAD-X element type and its attribute fragments. A
`BodyShiftP` comes back separately because MAD-X keeps a misalignment out of the element
definition and in an `EALIGN` command of its own. Unsupported parameter groups emit a message or
raise an error.
"""
function _make_madx_ele(ele::YAMLNode)
  props = ele[1]
  name = _madx_check_name(node_key(props))
  ele_kind = String(props["kind"])
  madx_kind = _madx_kind(ele_kind)

  attrs = String[]
  notes = String[]
  align = String[]
  # Strip a trailing comma (and surrounding whitespace) from a fragment before storing it.
  function push_attr!(s)
    t = rstrip(s)
    endswith(t, ",") && (t = rstrip(t[1:end-1]))
    isempty(t) || push!(attrs, t)
  end

  # The bend geometry has to be settled before anything else is: MAD-X holds a bend's geometry
  # and its field in the one `angle` attribute, and its arc length may be one PALS states only
  # by way of the geometry.
  geometry = madx_kind == "sbend" ? _madx_bend_geometry(props, name) : nothing
  ref_angle = geometry === nothing ? nothing : (geometry[1], geometry[2])
  arc_length = geometry === nothing ? nothing : geometry[3]

  for key in keys(props)
    if key == "length"
      if madx_kind in _MADX_THIN_KINDS
        Float64(props["length"]) ≈ 0 ||
            println("$name: a MAD-X $madx_kind has no length, so the PALS length is not " *
                    "translated")
      # A MAD-X multipole is thin: what length it has is the fictitious one used to work out
      # the radiation it emits.
      elseif madx_kind == "multipole"
        push_attr!("lrad = $(String(props["length"]))")
      else
        push_attr!("l = $(String(props["length"]))")
      end
    elseif key == "ACKickerP"
      error("$name: ACKickerP not yet supported")
    elseif key == "ApertureP"
      append!(attrs, _madx_aperture_attrs(props["ApertureP"], name, madx_kind))
    elseif key == "BeamBeamP"
      bbP = props["BeamBeamP"]
      for bbkey in keys(bbP)
        val = String(bbP[bbkey])
        if bbkey == "sigma_x"
          push_attr!("sigx = $val")
        elseif bbkey == "sigma_y"
          push_attr!("sigy = $val")
        elseif bbkey == "charge"
          push_attr!("charge = $val")
        elseif bbkey == "N_particle"
          push_attr!("npart = $val")
        else
          # MAD-X models the opposite beam as a four-dimensional lens: it has no place for its
          # length, its optics, or its energy.
          println("$name: BeamBeamP.$bbkey has no MAD-X equivalent, not translated")
        end
      end
    elseif key == "BendP"
      bendP = props["BendP"]

      # MAD-X states the geometry as an angle and an arc length, however PALS chose to write
      # the same thing; `_madx_bend_geometry` settled both above.
      arc_length === nothing || haskey(props, "length") || push_attr!("l = $arc_length")
      ref_angle === nothing || ref_angle[1] === nothing || push_attr!("angle = $(ref_angle[1])")
      append!(attrs, _madx_bend_faces(bendP, name, ref_angle === nothing ? nothing : ref_angle[1]))

      for bkey in keys(bendP)
        tmp = ""
        # Settled above: the geometry parameters, and the pole faces.
        if bkey in ("angle_ref", "g_ref", "radius_ref", "Bn0_ref", "L_chord", "L_rectangle",
                    "e1", "e2", "e1_rect", "e2_rect")
          continue

        # PALS states the fringe field as an integral with the gap folded in; MAD-X states the
        # dimensionless integral and the gap apart, so half of one is the whole of the other.
        elseif bkey == "edge1_int"
          val = Float64(bendP["edge1_int"])
          if !(val ≈ 0)
            tmp = "fint = 0.5, hgap = $(2val),"
          end
        elseif bkey == "edge2_int"
          val = Float64(bendP["edge2_int"])
          if !(val ≈ 0)
            tmp = "fintx = 0.5, hgapx = $(2val),"
          end

        elseif bkey == "h1"
          tmp = "h1 = $(String(bendP["h1"])),"
        elseif bkey == "h2"
          tmp = "h2 = $(String(bendP["h2"])),"
        elseif bkey == "tilt_ref"
          tmp = "tilt = $(String(bendP["tilt_ref"])),"
        # Whether the actual field defaults to the reference one, which is handled with the
        # multipoles below.
        elseif bkey == "Kn0_from_g_ref"
          continue
        elseif bkey == "L_sagitta"
          error("$name: BendP.L_sagitta is an output parameter and is not translated")
        # A MAD-X sbend is an arc whose multipoles are vertically pure; it has no equivalent of
        # the other geometries, nor of multipoles referred to something other than its own.
        elseif bkey == "ref_geometry"
          String(bendP[bkey]) == "ARC" ||
              println("$name: BendP.ref_geometry = $(String(bendP[bkey])) has no MAD-X " *
                      "equivalent; a MAD-X sbend is always an arc")
        elseif bkey == "multipole_geometry"
          String(bendP[bkey]) in ("FOLLOWS_REF_GEOMETRY", "VERTICALLY_PURE") ||
              println("$name: BendP.multipole_geometry = $(String(bendP[bkey])) has no MAD-X " *
                      "equivalent, not translated")
        end
        push_attr!(tmp)
      end

      # With `Kn0_from_g_ref` false and no order-0 multipole set, the bend has the geometry of
      # the reference bend and none of its field -- which MAD-X, tracking through the same
      # `angle` it builds the geometry from, cannot express.
      if haskey(bendP, "Kn0_from_g_ref") &&
             lowercase(String(bendP["Kn0_from_g_ref"])) == "false" &&
             !(haskey(props, "MagneticMultipoleP") &&
               any(k -> k in ("Kn0", "Bn0", "Kn0L", "Bn0L"), keys(props["MagneticMultipoleP"])))
        println("$name: Kn0_from_g_ref is false and no order-0 multipole is set, so the bend " *
                "has no actual field; MAD-X tracks through the same angle it bends the " *
                "reference orbit with and cannot hold the two apart")
      end
    elseif key == "BodyShiftP"
      bodyshiftP = props["BodyShiftP"]
      for bskey in keys(bodyshiftP)
        val = String(bodyshiftP[bskey])
        # MAD-X's DPHI turns the element the other way round from the right-hand rule the
        # other two follow, which is where the sign comes from.
        if bskey == "x_offset"
          push!(align, "dx = $val")
        elseif bskey == "y_offset"
          push!(align, "dy = $val")
        elseif bskey == "z_offset"
          push!(align, "ds = $val")
        elseif bskey == "x_rot"
          push!(align, "dphi = $(_madx_scale(val, -1))")
        elseif bskey == "y_rot"
          push!(align, "dtheta = $val")
        elseif bskey == "z_rot"
          push!(align, "dpsi = $val")
        end
      end
    elseif key == "CoordinateSetP"
      error("$name: MAD-X has no element that sets the global coordinates of the reference " *
            "curve, so CoordinateSetP cannot be translated")
    elseif key == "ElectricMultipoleP"
      error("$name: ElectricMultipoleP not yet supported")
    elseif key == "FloorP"
      error("$name: FloorP not yet supported")
    elseif key == "ForkP"
      error("$name: ForkP not yet supported")
    elseif key == "GirderP"
      error("$name: GirderP not yet supported")
    elseif key == "MagneticMultipoleP"
      full = FullRepresentation()
      full.L = haskey(props, "length") ? Float64(props["length"]) : 1.0
      _fill_multipoles!(full, props["MagneticMultipoleP"], name)

      # The orders that are the element's own become its strength attributes and leave `full`;
      # what is left has to go in a multipole array, which only a MAD-X multipole has.
      append!(attrs, _madx_native_strength!(full, ele_kind, name, ref_angle))
      if madx_kind == "multipole"
        append!(attrs, _madx_multipole_attrs(full, name))
      elseif !isempty(full.magnitude)
        orders = join(sort(collect(keys(full.magnitude))), ", ")
        println("$name: a MAD-X $madx_kind cannot carry multipoles of order $orders; they " *
                "need a multipole element of their own, not translated")
      end
    elseif key == "MetaP"
      metaP = props["MetaP"]
      # MAD-X elements hold no metadata of their own, so what PALS says about an element is
      # kept as a comment above it rather than dropped.
      for mkey in keys(metaP)
        val = metaP[mkey]
        if is_map(val) || is_sequence(val)
          println("$name: MetaP.$mkey is not a simple string, not translated")
          continue
        end
        push!(notes, "$mkey: $(String(val))")
      end
    elseif key == "PatchP"
      patchP = props["PatchP"]
      offsets = ["0", "0", "0"]
      angles  = ["0", "0", "0"]
      for pkey in keys(patchP)
        val = String(patchP[pkey])
        if pkey == "x_offset"
          offsets[1] = val
        elseif pkey == "y_offset"
          offsets[2] = val
        elseif pkey == "z_offset"
          offsets[3] = val
        elseif pkey == "x_rot"
          angles[1] = val
        elseif pkey == "y_rot"
          angles[2] = val
        elseif pkey == "z_rot"
          angles[3] = val
        else
          # A MAD-X changeref is the transformation and nothing else: it cannot be told to
          # work out its own offsets, nor which end its length is measured from.
          println("$name: PatchP.$pkey has no MAD-X equivalent, not translated")
        end
      end
      any(o -> o != "0", offsets) && push_attr!("patch_trans = {" * join(offsets, ", ") * "}")
      if any(a -> a != "0", angles)
        push_attr!("patch_ang = {" * join(angles, ", ") * "}")
        push!(notes, "MAD-X applies the three changeref angles in an order of its own; the " *
                     "PALS patch rotations match it only to first order in the angles.")
      end
    elseif key == "RFP"
      rfP = props["RFP"]
      if haskey(rfP, "frequency") && haskey(rfP, "harmon")
        error("$name: can only define `frequency` or `harmon` but not both")
      end
      # MAD-X's zero phase is the zero crossing half a period away from the one PALS calls the
      # stable point above transition, whichever of the three PALS is measuring from.
      zero_phase = haskey(rfP, "zero_phase") ? String(rfP["zero_phase"]) : "ACCELERATING"
      lag_offset = zero_phase == "ABOVE_TRANSITION" ? -0.5 :
                   zero_phase == "BELOW_TRANSITION" ?  0.0 :
                   zero_phase == "ACCELERATING"     ? -0.25 :
                   error("$name: unknown zero_phase `$zero_phase`")

      for rfkey in keys(rfP)
        tmp = ""
        # PALS states the frequency in Hz and the voltage in volts, MAD-X in MHz and MV.
        if rfkey == "frequency"
          tmp = "freq = $(_madx_scale(String(rfP["frequency"]), 1e-6)),"
        elseif rfkey == "harmon"
          tmp = "harmon = $(String(rfP["harmon"])),"
        elseif rfkey == "voltage"
          tmp = "volt = $(_madx_scale(String(rfP["voltage"]), 1e-6)),"
        elseif rfkey == "gradient"
          L = haskey(rfP, "L_active") ? String(rfP["L_active"]) :
              haskey(props, "length") ? String(props["length"]) : nothing
          L === nothing &&
              error("$name: `gradient` needs a length to become the voltage MAD-X states")
          tmp = "volt = $(_madx_scale(String(rfP["gradient"]), 1e-6)) * $L,"
        elseif rfkey == "phase"
          tmp = "lag = $(_madx_shift(String(rfP["phase"]), lag_offset)),"
        elseif rfkey == "cavity_type"
          String(rfP["cavity_type"]) == "TRAVELING_WAVE" &&
              println("$name: a traveling wave cavity is MAD-X's twcavity, which only PTC " *
                      "tracks; translated as an rfcavity")
        elseif rfkey in ("multipass_phase", "num_cells", "L_active", "dE_ref")
          println("$name: RFP.$rfkey has no MAD-X equivalent, not translated")
        end
        push_attr!(tmp)
      end
      # A phase of zero still has to be written out: MAD-X measures it from somewhere else.
      haskey(rfP, "phase") || lag_offset == 0 || push_attr!("lag = $lag_offset")
    elseif key == "SolenoidP"
      solP = props["SolenoidP"]
      if haskey(solP, "Ksol")
        push_attr!("ks = $(String(solP["Ksol"]))")
      elseif haskey(solP, "Bsol")
        push_attr!("ks = $(_madx_divide(String(solP["Bsol"]), _MADX_RIGIDITY))")
      elseif !isempty(keys(solP))
        println("$name - unknown SolenoidP key(s): $(keys(solP))")
      end
      # A thin MAD-X solenoid states its integrated strength instead, `ks` alone doing nothing.
      haskey(props, "length") && Float64(props["length"]) == 0 &&
          println("$name: a solenoid of zero length also needs MAD-X's ksi, which PALS does " *
                  "not state")
    elseif key == "TaylorP"
      error("$name: TaylorP is not yet translated to a MAD-X matrix")
    elseif key == "TrackingP"
      # Tracking parameters are program specific by design; MAD-X's have no PALS spelling.
    elseif key == "ReferenceChangeP"
      error("$name: MAD-X takes the reference energy from the BEAM command and cannot change " *
            "it in mid-line")
    end
  end

  return MadxEleDef(name, madx_kind, attrs, notes), MadxAlignment(name, align)
end

#---------------------------------------------------------------------------------------------------
"""
    _madx_control_target(cname::String, param::String, facility::YAMLNode)

Translate a controller's `parameter` target into a MAD-X attribute reference.

Return `(target, factor, rigidity)` where `target` is the `"ele->attribute"` MAD-X reference,
the control expression must be multiplied by `factor`, and `rigidity` says whether it must also
be divided by the reference rigidity to hold the same physics. Neither is trivial in general
because the element translation does not carry PALS parameters across unchanged: the attribute a
multipole lands in may be length integrated where the PALS parameter was not, or the other way
round, and a stated field has to be normalized because MAD-X has no field-valued attribute.

A target may name its element by kind as well as by name, as `{kind}::{name}`; the qualifier is
checked against the element found and then dropped, MAD-X having one namespace for all of them.

Targets MAD-X cannot express -- a pattern matching several elements, a `>>` or `>>>` qualifier
naming the BeamLine or Lattice an element is reached through, a parameter with no MAD-X
attribute, or an order that only a multipole array could hold, MAD-X having no way to name one
entry of one -- raise an error.
"""
function _madx_control_target(cname::String, param::String, facility::YAMLNode,
                              varmap::Dict{Tuple{String,String},String})
  occursin(">>", param) &&
      error("controller $cname: `$param` reaches its element through a BeamLine or Lattice " *
            "qualifier, which MAD-X, having one namespace for the whole file, cannot express")

  parts = split(param, ">")
  length(parts) == 2 ||
      error("controller $cname: control parameter `$param` is not of the form `element>parameter`")
  slave, path = String(parts[1]), String(parts[2])

  # An element may be named by its kind as well as by its name.
  kind_wanted = nothing
  if occursin("::", slave)
    qualifier = split(slave, "::")
    length(qualifier) == 2 ||
        error("controller $cname: `$param` does not name a single element kind")
    kind_wanted, slave = String(qualifier[1]), String(qualifier[2])
  end

  occursin(r"^[A-Za-z_][A-Za-z0-9_]*$", slave) ||
      error("controller $cname: `$param` selects slaves by pattern, which MAD-X cannot express")

  props = _facility_props(facility, slave)
  props === nothing && error("controller $cname: `$param` names no element of the facility")
  ele_kind = haskey(props, "kind") ? String(props["kind"]) : ""
  kind_wanted === nothing || kind_wanted == ele_kind ||
      error("controller $cname: `$param` asks for a $kind_wanted but $slave is a $ele_kind")

  # A controller may drive another controller's variable, under whatever MAD-X calls it.
  if ele_kind == "Controller"
    occursin(r"^[A-Za-z_][A-Za-z0-9_]*$", path) ||
        error("controller $cname: `$param` is not a variable of controller $slave")
    haskey(varmap, (slave, path)) ||
        error("controller $cname: `$param` names no variable of controller $slave")
    return varmap[(slave, path)], 1.0, false
  end

  path == "length" && return "$slave->l", 1.0, false

  m = match(r"^MagneticMultipoleP\.([KB])([ns])([0-9]+)(L?)$", path)
  if m !== nothing
    order      = parse(Int, m[3])
    skew       = m[2] == "s"
    integrated = m[4] == "L"
    normalized = m[1] == "K"
    ele_length = haskey(props, "length") ? Float64(props["length"]) : 1.0

    # A tilted multipole rotates normal and skew into each other, so the one PALS parameter no
    # longer maps onto the one MAD-X attribute.
    if haskey(props, "MagneticMultipoleP") && haskey(props["MagneticMultipoleP"], "tilt$order")
      Float64(props["MagneticMultipoleP"]["tilt$order"]) ≈ 0 ||
          error("controller $cname: `$param` drives a tilted multipole, which has no single " *
                "MAD-X attribute")
    end

    native = get(_MADX_NATIVE_STRENGTH, ele_kind, Dict{Tuple{Int,Bool},String}())
    attribute = get(native, (order, skew), nothing)
    attribute === nothing &&
        error("controller $cname: a MAD-X $(_madx_kind(ele_kind)) has no attribute for " *
              "`$param`; MAD-X cannot name one entry of a multipole array")

    factor = 1.0
    if attribute in _MADX_INTEGRATED_STRENGTH && !integrated
      factor = ele_length
    elseif !(attribute in _MADX_INTEGRATED_STRENGTH) && integrated
      ele_length == 0 &&
          error("controller $cname: `$param` is integrated over an element of zero length, " *
                "which MAD-X's `$attribute` cannot state")
      factor = 1 / ele_length
    end
    attribute == "hkick" && (factor = -factor)

    return "$slave->$attribute", factor, !normalized
  end

  error("controller $cname: control parameter `$param` is not yet translated to MAD-X")
end

#---------------------------------------------------------------------------------------------------
"""
    _madx_base_value(lat::MadxLattice, target::String)

Return the value `target` already holds, as written by the element translation.

A `control_type: RELATIVE` controller varies a parameter rather than setting it, and a MAD-X
deferred assignment can only set one: `ele->k1 := ele->k1 + dk` is the circular definition MAD-X
forbids. So the value being varied has to be written into the assignment, and the one place it
is written down is the definition this reads it back out of.
"""
function _madx_base_value(lat::MadxLattice, target::String, initials::Dict{String,String})
  parts = split(target, "->")
  # A bare name is another controller's variable, whose value is its initial setting.
  length(parts) == 1 && return get(initials, target, "0")

  ele_name, attribute = String(parts[1]), String(parts[2])
  for ele in lat.elements
    ele.name == ele_name || continue
    for attr in ele.attrs
      m = match(r"^\s*([A-Za-z_][A-Za-z0-9_]*)\s*=\s*(.*)$", attr)
      m === nothing && continue
      lowercase(String(m[1])) == lowercase(attribute) && return String(m[2])
    end
    return "0"
  end
  return "0"
end

#---------------------------------------------------------------------------------------------------
"""
    _make_madx_controller(ele, facility, lat, varmap, initials)

Translate a `Controller` element into a [`MadxController`](@ref).

`facility` is needed to reach the slave elements: what a control expression must be scaled by
depends on the element it drives (see [`_madx_control_target`](@ref)). `varmap` and `initials`
carry what each controller variable is called in the MAD-X file and what it starts at (see
[`_madx_variable_names`](@ref)). `lat` is needed for a `RELATIVE` controller, whose slaves keep
the value their element definitions already gave them.

The two control types part company here. An `ABSOLUTE` controller sets its slaves outright, and
a deferred assignment does the same. A `RELATIVE` one is a knob: its slaves keep the value the
lattice gave them and move by however far the knob has been turned *from where it started*, so
the assignment is the element's own value, plus the expression, less the expression at the
variables' initial settings. That last term is what a Bmad `group` keeps track of by itself and
MAD-X has nothing for; it is left out only when it can be shown to come to zero, which for a
knob resting at zero it does.
"""
function _make_madx_controller(ele::YAMLNode, facility::YAMLNode, lat::MadxLattice,
                               varmap::Dict{Tuple{String,String},String},
                               initials::Dict{String,String})
  props = ele[1]
  name = _madx_check_name(node_key(props))

  control_type = haskey(props, "control_type") ? String(props["control_type"]) : "ABSOLUTE"
  control_type in ("ABSOLUTE", "RELATIVE") ||
      error("$name: control_type must be ABSOLUTE or RELATIVE, not $control_type")

  vars = String[]
  renames  = Dict{String,String}()   # variable -> what MAD-X calls it
  starting = Dict{String,String}()   # variable -> where it starts
  for (var, value) in _ctrl_variables(props)
    madx = varmap[(name, var)]
    push!(vars, "$(_madx_check_name(madx)) = $(_madx_check_expression(name, value))")
    renames[var]  = madx
    starting[var] = "($value)"
  end

  # A controller may carry a MetaP, which MAD-X has nowhere to put but a comment.
  notes = String[]
  if haskey(props, "MetaP")
    metaP = props["MetaP"]
    for mkey in keys(metaP)
      val = metaP[mkey]
      if is_map(val) || is_sequence(val)
        println("$name: MetaP.$mkey is not a simple string, not translated")
        continue
      end
      push!(notes, "$mkey: $(String(val))")
    end
  end

  controls = String[]
  if haskey(props, "controls")
    for control in props["controls"]
      haskey(control, "parameter") && haskey(control, "expression") ||
          error("$name: a controls entry needs both a `parameter` and an `expression`")
      target, factor, rigidity =
          _madx_control_target(name, String(control["parameter"]), facility, varmap)

      pals_expr = String(control["expression"])
      # The same scaling the element attribute was given, whichever form of the expression it
      # is being applied to.
      function scaled(expr)
        factor ≈ 1 || (expr = "$factor*($expr)")
        rigidity && (expr = "($expr) / $_MADX_RIGIDITY")
        return expr
      end
      expression = scaled(_madx_check_expression(name, _madx_substitute(pals_expr, renames)))

      if control_type == "RELATIVE"
        expression = "$(_madx_base_value(lat, target, initials)) + ($expression)"
        at_start = _madx_substitute(pals_expr, starting)
        # A knob that starts where its expression comes to zero has moved nothing yet, and
        # needs no term saying so. Anything the standalone evaluator cannot reach -- a
        # user-defined constant, say -- is written out and left for MAD-X.
        zero_at_start = try
          evaluate_pals_expression(at_start) ≈ 0
        catch
          false
        end
        zero_at_start || (expression *= " - ($(scaled(at_start)))")
      end
      push!(controls, "$target := $expression")
    end
  end

  return MadxController(name, vars, controls, notes)
end
