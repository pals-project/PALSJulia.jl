"""
    BmadEleDef

A single Bmad element definition.

Fields:
  - `name`  : the element name.
  - `type`  : the Bmad element-type name (e.g. `Drift`, `Quadrupole`).
  - `attrs` : already-translated attribute fragments, each an `"attribute = value"` string.
"""
struct BmadEleDef
  name::String
  type::String
  attrs::Vector{String}
end

#---------------------------------------------------------------------------------------------------
"""
    BmadBeamline

A Bmad `line` definition: its `name` and the ordered list of member element `members` (by name).
"""
struct BmadBeamline
  name::String
  members::Vector{String}
end

#---------------------------------------------------------------------------------------------------
"""
    BmadLattice

An in-memory model of a Bmad lattice.

Produced by [`pals_to_bmad`](@ref) and serialized to a file by [`write_bmad_file`](@ref).
The fields mirror the sections of a Bmad lattice file:
  - `parameters`     : global `parameter[...] = ...` settings (species, energy, geometry).
  - `particle_start` : `particle_start[...] = ...` initial-coordinate settings.
  - `elements`       : element definitions ([`BmadEleDef`](@ref)).
  - `beamlines`      : `line` definitions ([`BmadBeamline`](@ref)).
  - `use`            : branch names for the final `use, ...` statement.
"""
struct BmadLattice
  parameters::Vector{String}
  particle_start::Vector{String}
  elements::Vector{BmadEleDef}
  beamlines::Vector{BmadBeamline}
  use::Vector{String}
end
BmadLattice() = BmadLattice(String[], String[], BmadEleDef[], BmadBeamline[], String[])

#---------------------------------------------------------------------------------------------------
"""
    pals_to_bmad(file_dir::String)

Read the PALS-YAML lattice file at `file_dir` and translate it into a [`BmadLattice`](@ref).

The returned structure is an in-memory model of the *Bmad* lattice (elements, beamlines,
parameters), not the input PALS tree. Pass it to [`write_bmad_file`](@ref) to emit a Bmad
lattice file; `write_bmad_file(pals_to_bmad(file_dir), filename)` performs the full translation.
"""
function pals_to_bmad(file_dir::String)
  yaml = parse_file(file_dir)
  facility = yaml["PALS"]["facility"]
  lat = BmadLattice()
  N_lattices = 0
  for ele in facility
    props = ele[1]
    haskey(props, "kind") || continue
    pals_kind = String(props["kind"])
    if pals_kind == "BeginningEle"
      params, particle = _ele_to_bmad_str(ele)
      append!(lat.parameters, params)
      append!(lat.particle_start, particle)
    elseif pals_kind == "BeamLine"
      push!(lat.beamlines, _make_bmad_line(ele))
    elseif pals_kind == "Lattice"
      N_lattices += 1
      N_lattices > 1 && error("\n
                Different BeamLine complexes must be translated from separate files.\n
                Bmad only supports one branching lattice per file.\n
                Consider using different Tao universes.\n")
      _add_bmad_branches!(lat, props["branches"])
    else
      push!(lat.elements, _make_bmad_ele(ele))
    end
  end
  return lat
end

#---------------------------------------------------------------------------------------------------
"""
    _add_bmad_branches!(lat::BmadLattice, branches)

Translate a PALS `Lattice`'s `branches` sequence into `lat`.

Append each branch name to `lat.use` and its geometry to `lat.parameters` (`parameter[geometry]`
for a single branch, `<name>[geometry]` when several branches are present).
"""
function _add_bmad_branches!(lat::BmadLattice, branches)
  isempty(branches) && return lat
  single = length(branches) == 1
  for bl in branches
    if is_scalar(bl)
      name = String(bl)
      periodic = "open"
    elseif is_map(bl)
      bl_props = bl[1]
      name = node_key(bl_props)
      periodic = (haskey(bl_props, "periodic") && bl_props["periodic"] == "true") ? "closed" : "open"
    elseif is_sequence(bl)
      error("Expanding lattices is not done during PALS>Bmad translation")
    else
      error("This object is neither a scalar, map, nor sequence: ", bl)
    end
    push!(lat.use, name)
    if single
      push!(lat.parameters, "parameter[geometry] = $periodic")
    else
      push!(lat.parameters, "$name[geometry] = $periodic")
    end
  end
  return lat
end

#---------------------------------------------------------------------------------------------------
"""
    write_bmad_file(lat::BmadLattice, filename::String)

Serialize the [`BmadLattice`](@ref) `lat` to `filename` as a Bmad lattice file.

Write the global/particle-start parameters, the element definitions, the beamline (`line`)
definitions, and the branch (`use`) statement, each in its own labelled section.
"""
function write_bmad_file(lat::BmadLattice, filename::String)
  open(filename, "w") do io
    for p in lat.parameters
      write(io, p * "\n")
    end
    if !isempty(lat.particle_start)
      write(io, "\n")
      for p in lat.particle_start
        write(io, p * "\n")
      end
    end
    write(io, "\n!======================================================================" * "\n")
    write(io, "! Element definitions " * "\n\n")
    for ele in lat.elements
      write(io, _format_bmad_ele(ele) * "\n")
    end
    write(io, "!======================================================================" * "\n")
    write(io, "! Beamline definitions " * "\n\n")
    for bl in lat.beamlines
      write(io, _format_bmad_line(bl) * "\n\n")
    end
    write(io, "!======================================================================" * "\n")
    write(io, "! Branch structure " * "\n\n")
    !isempty(lat.use) && write(io, "use, " * join(lat.use, ", "))
  end
  return nothing
end

#---------------------------------------------------------------------------------------------------
"""
    _format_bmad_ele(ele::BmadEleDef)

Render a [`BmadEleDef`](@ref) as a `name: type, attr = val, ...` Bmad element definition, with
each attribute on its own tab-indented continuation line.
"""
function _format_bmad_ele(ele::BmadEleDef)
  s = "$(ele.name): $(ele.type)"
  for a in ele.attrs
    s *= ",\n\t$a"
  end
  return s
end

#---------------------------------------------------------------------------------------------------
"""
    _format_bmad_line(bl::BmadBeamline)

Render a [`BmadBeamline`](@ref) as a Bmad `name: line = (...)` definition, wrapping the member
list with tab-indented continuation lines to keep rows under ~80 columns.
"""
function _format_bmad_line(bl::BmadBeamline)
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
  return "$(bl.name): line = ($wrapped)"
end

#---------------------------------------------------------------------------------------------------
"""
    _ele_to_bmad_str(ele::YAMLNode)

Translate a `BeginningEle` element into Bmad global-parameter settings.

Return `(params, particle_start)` where `params` holds `parameter[...]` strings from the
element's `ReferenceP` (species and energy) and `particle_start` holds `particle_start[...]`
strings from its `ParticleP` (initial phase-space coordinates).
"""
function _ele_to_bmad_str(ele::YAMLNode)
  props = ele[1]
  params = String[]
  particle = String[]
  for key in keys(props)
    if key == "ReferenceP"
      referenceP = props["ReferenceP"]
      for k in keys(referenceP)
        if k == "species_ref"
          push!(params, "parameter[particle] = $(String(referenceP[k]))")
        elseif k == "pc_ref"
          push!(params, "parameter[p0c] = $(String(referenceP[k]))")
        elseif k == "E_tot_ref"
          push!(params, "parameter[E_tot] = $(String(referenceP[k]))")
        elseif k == "time_ref" || k == "location"
          println("$k not supported yet")
        end
      end
    elseif key == "ParticleP"
      particleP = props["ParticleP"]
      for k in keys(particleP)
        val = String(particleP[k])
        if k == "x"
          push!(particle, "particle_start[x] = $val")
        elseif k == "y"
          push!(particle, "particle_start[y] = $val")
        elseif k == "z"
          push!(particle, "particle_start[z] = $val")
        elseif k == "px"
          push!(particle, "particle_start[px] = $val")
        elseif k == "py"
          push!(particle, "particle_start[py] = $val")
        elseif k == "pz"
          push!(particle, "particle_start[pz] = $val")
        end
      end
    end
  end
  return params, particle
end

#---------------------------------------------------------------------------------------------------
"""
    _make_bmad_line(ele::YAMLNode)

Translate a `BeamLine` element into a [`BmadBeamline`](@ref).

Collect the member element names (dropping the leading reference entry, `line[1]`, by design)
into the returned beamline.
"""
function _make_bmad_line(ele::YAMLNode)
  props = ele[1]
  name = node_key(props)
  line = props["line"]
  members = String[]
  for i in 2:length(line)
    line_ele = line[i]
    if is_scalar(line_ele)
      push!(members, String(line_ele))
    elseif is_map(line_ele) || is_sequence(line_ele)
      push!(members, node_key(line_ele[1]))
    else
      error("BeamLine $name element $i is not scalar or sequence or map")
    end
  end
  return BmadBeamline(name, members)
end

#---------------------------------------------------------------------------------------------------
"""
    _bmad_kind(ele_kind::String)

Map a PALS element kind to its Bmad counterpart.

Return `(bmad_kind, args)` where `bmad_kind` is the Bmad element-type name for the PALS
`ele_kind`. Kinds with no Bmad equivalent (e.g. `UnionEle`, `Feedback`) raise an error.
"""
function _bmad_kind(ele_kind::String)
  # Magnets and RF Cavities
  if      ele_kind == "ACKicker";         return ("AC_Kicker", nothing)
  elseif  ele_kind == "RBend";            return (ele_kind, nothing)
  elseif  ele_kind == "SBend";            return (ele_kind, nothing)
  elseif  ele_kind == "CrabCavity";       return ("Crab_Cavity", nothing)
  elseif  ele_kind == "Drift";            return (ele_kind, nothing)
  elseif  ele_kind == "Kicker";           return (ele_kind, nothing)
  elseif  ele_kind == "Multipole";        return ("AB_Multipole", nothing)
  elseif  ele_kind == "Octupole";         return (ele_kind, nothing)
  elseif  ele_kind == "Quadrupole";       return (ele_kind, nothing)
  elseif  ele_kind == "RFCavity";         return (ele_kind, nothing)
  elseif  ele_kind == "Sextupole";        return (ele_kind, nothing)
  elseif  ele_kind == "Solenoid";         return (ele_kind, nothing)
  elseif  ele_kind == "Wiggler";          return (ele_kind, nothing)

  # Beam and Plasma Elements
  elseif  ele_kind == "BeamBeam";         return (ele_kind, nothing)

  # Sources and Collimation
  elseif  ele_kind == "Converter";        return (ele_kind, nothing)
  elseif  ele_kind == "EGun";             return ("E_Gun", nothing)
  elseif  ele_kind == "Foil";             return (ele_kind, nothing)
  elseif  ele_kind == "Mask";             return (ele_kind, nothing)

  # Instrumentation and Diagnostics
  elseif  ele_kind == "Instrument";       return (ele_kind, nothing)

  # Map Elements
  elseif  ele_kind == "Match";            return (ele_kind, nothing)
  elseif  ele_kind == "Taylor";           return (ele_kind, nothing)

  # Bookkeeping Elements
  elseif  ele_kind == "BeginningEle";     return ("Beginning_Ele", nothing)
  elseif  ele_kind == "Fiducial";         return (ele_kind, nothing)
  elseif  ele_kind == "FloorShift";       return ("Floor_Shift", nothing)
  elseif  ele_kind == "Fork";             return (ele_kind, nothing)
  elseif  ele_kind == "Marker";           return (ele_kind, nothing)
  elseif  ele_kind == "Placeholder";      return ("Marker", nothing) # ?
  elseif  ele_kind == "Patch";            return (ele_kind, nothing)
  elseif  ele_kind == "ReferenceChange";  return ("Patch", nothing)

  # Structural and Grouping Elements
  elseif  ele_kind == "Girder";           return (ele_kind, nothing)
  elseif  ele_kind == "UnionEle";         return error("No UnionEle in Bmad")

  # External Circuits
  elseif  ele_kind == "Feedback";         return error("No Feedback elements in Bmad")

  end
end

#---------------------------------------------------------------------------------------------------
"""
    MultipoleRepresentation

Abstract supertype for the multipole representations used during PALS-to-Bmad translation.

Concrete subtypes are [`FullRepresentation`](@ref) (the raw, over-parametrized form read
from PALS-YAML) and [`ABRepresentation`](@ref) (the element-specific A/B field integrals).
"""
abstract type MultipoleRepresentation end

#---------------------------------------------------------------------------------------------------
"""
    FullRepresentation <: MultipoleRepresentation

Raw, over-parametrized multipole form filled directly from PALS-YAML.

Holds, keyed by multipole order, whether each coefficient is `normalized` (K vs. B) and
`integrated` (field integral vs. field strength), its `magnitude` (normal/skew pair), and its
`tilt`, together with the element length `L`. It is down-converted to whichever
element-specific representation the element kind requires.

    FullRepresentation()

Construct an empty representation with unit length `L`.
"""
mutable struct FullRepresentation <: MultipoleRepresentation
  normalized::Dict{Int,Bool}
  integrated::Dict{Int,Bool}
  magnitude ::Dict{Int,Vector{Float64}}
  tilt      ::Dict{Int,Float64}
  L         ::Float64
end
FullRepresentation() = FullRepresentation(Dict(), Dict(), Dict(), Dict(), 1.0)
FullRepresentation(full::FullRepresentation) = full   # identity down-convert

#---------------------------------------------------------------------------------------------------
"""
    ABRepresentation <: MultipoleRepresentation

Element-specific multipole form: only the final A/B field integrals.

`A` and `B` map each multipole order to its skew and normal field integral, respectively.
Built from a [`FullRepresentation`](@ref) via [`ABRepresentation(::FullRepresentation)`](@ref).
"""
struct ABRepresentation <: MultipoleRepresentation
  A::Dict{Int,Float64}
  B::Dict{Int,Float64}
end

#---------------------------------------------------------------------------------------------------
"""
    ABRepresentation(full::FullRepresentation)

Down-convert a `FullRepresentation` to A/B field integrals.

Combine each multipole's magnitude, length, and tilt into complex field integrals and store
their imaginary/real parts as the `A`/`B` coefficient dictionaries.
"""
function ABRepresentation(full::FullRepresentation)
  A = Dict{Int,Float64}()
  B = Dict{Int,Float64}()
  for mp in keys(full.magnitude)
    L    = full.integrated[mp] ? 1.0 : full.L
    t_n  = haskey(full.tilt, mp) ? full.tilt[mp] : 0.0
    fact = mp <= 20 ? 1 / factorial(mp) : 1 / factorial(big(mp))
    b_ia = fact * L * first([1 1im] * full.magnitude[mp]) * exp(-1im * mp * t_n)
    A[mp] = imag(b_ia)
    B[mp] = real(b_ia)
  end
  return ABRepresentation(A, B)
end

#---------------------------------------------------------------------------------------------------
"""
    _KindMap(ele_kind)

Return the multipole representation type used for a given element kind.

Elements that carry field multipoles map to `ABRepresentation`; kinds that have no multipole
attributes, or are unrecognized, raise an error.
"""
function _KindMap(ele_kind)
  if ele_kind in ("SBend", "RBend", "Quadrupole", "Sextupole", "Octupole",
          "Multipole", "Solenoid", "Kicker", "Wiggler",
          "RFCavity", "CrabCavity")
    return ABRepresentation
  elseif ele_kind in ("EGun", "Mask", "Converter", "Instrument")
    return error("Bmad $ele_kind has no multipole attributes")
  else
    error("Element type $ele_kind is unrecognized")
  end
end

#---------------------------------------------------------------------------------------------------
"""
    _fill_multipoles!(full::FullRepresentation, mmP, name)

Populate `full` from a PALS `MagneticMultipoleP` map.

Parse each key of `mmP` into a multipole order and store its magnitude, `normalized`,
`integrated`, and `tilt` attributes in `full`; `name` is used in error messages. Return `full`.
"""
function _fill_multipoles!(full::FullRepresentation, mmP, name)
  for mmkey in keys(mmP)
    order = parse(Int, filter(isdigit, mmkey))
    if startswith(mmkey, "tilt")
      haskey(full.tilt, order) && error("$name conflicting multipole definitions $mmkey")
      full.tilt[order] = Float64(mmP[mmkey])
    else
      ns = mmkey[2] == 'n' ? 1 : 2
      if !haskey(full.magnitude, order)
        full.integrated[order] = (mmkey[end] == 'L')
        full.normalized[order] = (mmkey[1] == 'K')
        full.magnitude[order]  = zeros(Float64, 2)
      end
      full.magnitude[order][ns] = Float64(mmP[mmkey])
    end
  end
  return full
end

#---------------------------------------------------------------------------------------------------
"""
    _mp_key(rep::ABRepresentation)

Return the Bmad attribute fragments for A/B field-integral multipoles.

Emit an `An = ...` / `Bn = ...` fragment for each nonzero coefficient in `rep`.
"""
function _mp_key(rep::ABRepresentation)
  out = String[]
  for mp in keys(rep.A)
    if !(rep.A[mp] ≈ 0)
      push!(out, "A$mp = $(rep.A[mp])")
    end
    if !(rep.B[mp] ≈ 0)
      push!(out, "B$mp = $(rep.B[mp])")
    end
  end
  return out
end

#---------------------------------------------------------------------------------------------------
"""
    _mp_key(rep::FullRepresentation)

Return the Bmad attribute fragments for the raw multipole representation.

Emit `Kn...L`, `Kn...SL`, and tilt fragments for each multipole in `rep`.
"""
function _mp_key(rep::FullRepresentation)
  out = String[]
  for mp in keys(rep.normalized)
    val = rep.integrated[mp] ? rep.magnitude[mp][1] : rep.magnitude[mp][1] * rep.L
    push!(out, "Kn$(mp)L = $val")
    if rep.magnitude[mp][2] != 0
      push!(out, "Kn$(mp)SL = $(rep.magnitude[mp][2])")
    end
    if haskey(rep.tilt, mp)
      push!(out, "T$mp = $(rep.tilt[mp])")
    end
  end
  return out
end

#---------------------------------------------------------------------------------------------------
"""
    _make_bmad_ele(ele::YAMLNode)

Translate a single PALS element into a [`BmadEleDef`](@ref).

Dispatch on the element `kind` and its parameter groups (aperture, bend, body shift,
multipoles, patch, RF, solenoid, reference change, ...) to build the Bmad element type and its
attribute fragments. Unsupported parameter groups emit a message or raise an error.
"""
function _make_bmad_ele(ele::YAMLNode)
  props = ele[1]
  ele_kind = String(props["kind"])
  ele_kind_bmad, args = _bmad_kind(ele_kind)

  attrs = String[]
  # Strip a trailing comma (and surrounding whitespace) from a fragment before storing it.
  function push_attr!(s)
    t = rstrip(s)
    endswith(t, ",") && (t = rstrip(t[1:end-1]))
    isempty(t) || push!(attrs, t)
  end

  for key in keys(props)
    if key == "length"
      push_attr!("L = $(String(props["length"]))")
    elseif key == "ACKickerP"
      error("ACKickerP not yet supported")
    elseif key == "ApertureP"
      apertureP = props["ApertureP"]

      tmp = ""
      has_xmin   = haskey(apertureP, "x_min");    has_xmax  = haskey(apertureP, "x_max")
      has_xwidth = haskey(apertureP, "x_width");  has_xcen  = haskey(apertureP, "x_center")
      if (has_xmin || has_xmax) && (has_xwidth || has_xcen)
        println("
                Ignoring ApertureP of element $(node_key(ele[1])).
                Either x_min and max should be defined or width and center, not both.
                ")
      elseif (has_xwidth)
        width  = Float64(apertureP["x_width"])
        center = has_xcen ? Float64(apertureP["x_center"]) : 0.0
        tmp *= "x1_limit = $(width / 2 - center), "
        tmp *= "x2_limit = $(width / 2 + center),"
      elseif (has_xmin && has_xmax)
        tmp *= "x1_limit = $(String(apertureP["x_min"])), "
        tmp *= "x2_limit = $(String(apertureP["x_max"])),"
      end
      push_attr!(tmp)

      tmp = ""
      has_ymin   = haskey(apertureP, "y_min");    has_ymax  = haskey(apertureP, "y_max")
      has_ywidth = haskey(apertureP, "y_width");  has_ycen  = haskey(apertureP, "y_center")
      if (has_ymin || has_ymax) && (has_ywidth || has_ycen)
        println("
                Ignoring ApertureP of element $(node_key(ele[1])).
                Either y_min and max should be defined or width and center, not both.
                ")
      elseif (has_ywidth)
        width  = Float64(apertureP["y_width"])
        center = has_ycen ? Float64(apertureP["y_center"]) : 0.0
        tmp *= "y1_limit = $(width / 2 - center), "
        tmp *= "y2_limit = $(width / 2 + center),"
      elseif (has_ymin && has_ymax)
        tmp *= "y1_limit = $(String(apertureP["y_min"])), "
        tmp *= "y2_limit = $(String(apertureP["y_max"])),"
      end
      push_attr!(tmp)

      for akey in keys(apertureP)
        tmp = ""
        if akey == "shape"
          shape = String(apertureP["shape"])
          if shape == "ELLIPTICAL"
            tmp *= "aperture_type = elliptical,"
          elseif shape == "RECTANGULAR"
            tmp *= "aperture_type = rectangular,"
          else
            error("shape $shape is not supported")
          end
        elseif akey == "location"
          location = String(apertureP["location"])
          if location == "ENTRANCE_END"
            tmp *= "aperture_at = entrance_end,"
          elseif location == "EXIT_END"
            tmp *= "aperture_at = exit_end,"
          elseif location == "BOTH_ENDS" || (location == "CENTER" && println("location=CENTER not supported, set to aperture_at=both_ends"))
            tmp *= "aperture_at = both_ends,"
          elseif location == "EVERYWHERE"
            tmp *= "aperture_at = continuous,"
          elseif location == "NOWHERE"
            tmp *= "aperture_at = no_aperture,"
          end
        elseif akey == "aperture_shifts_with_body"
          shifts = lowercase(String(apertureP["aperture_shifts_with_body"]))
          tmp *= "offset_moves_aperture = $(shifts == "true" ? "T" : "F"),"
        elseif akey == "aperture_active"
          active = lowercase(String(apertureP["aperture_active"]))
          tmp *= "is_on = $(active == "true" ? "T" : "F"),"
        elseif akey == "vertices"
          println("vertices not yet supported")
        elseif akey == "material"
          println("material not yet supported")
        elseif akey == "thickness"
          println("thickness not yet supported")
        end
        push_attr!(tmp)
      end
    elseif key == "BeamBeamP"
      bbP = props["BeamBeamP"]
      error("$(node_key(props)): BeamBeamP not translated yet")
    elseif key == "BendP"
      bendP = props["BendP"]
      has_e1 = haskey(bendP, "e1");  has_e1_rect  = haskey(bendP, "e1_rect");
      has_e2 = haskey(bendP, "e2");  has_e2_rect  = haskey(bendP, "e2_rect");
      if (has_e1 || has_e2) && (has_e1_rect || has_e2_rect)
        error("$(node_key(props)): should not have both e1 and e1_rect, nor both e2 and e2_rect")
      end

      for bkey in keys(bendP)
        tmp = ""
        if bkey == "rho_ref"
          tmp *= "angle = $(String(bendP["rho_ref"])),"
        elseif bkey == "bend_field_ref"
          tmp *= "B_field = $(String(bendP["bend_field_ref"])),"

        elseif bkey == "e1" || bkey == "e1_rect"
          tmp *= "e1 = $(String(bendP["e1"])),"
        elseif bkey == "e2" || bkey == "e2_rect"
          tmp *= "e2 = $(String(bendP["e2"])),"

        elseif bkey == "edge1_int"
          val = Float64(bendP["edge1_int"])
          if !(val ≈ 0)
            tmp *= "fint = 0.5, "
            tmp *= "hgap = $(2val),"
          end
        elseif bkey == "edge2_int"
          val = Float64(bendP["edge2_int"])
          if !(val ≈ 0)
            tmp *= "fintx = 0.5, "
            tmp *= "hgapx = $(2val),"
          end
        elseif bkey == "g_ref"
          tmp *= "g = $(String(bendP["g_ref"])),"
        elseif bkey == "h1"
          tmp *= "h1 = $(String(bendP["h1"])),"
        elseif bkey == "h2"
          tmp *= "h2 = $(String(bendP["h2"])),"
        elseif bkey == "L_chord"
          error("$(node_key(props)): L_chord is a derived quantity for SBend elements")
        elseif bkey == "L_sagitta"
          error("$(node_key(props)): L_sagitta is a derived quantity for SBend/RBend elements")
        elseif bkey == "tilt_ref"
          tmp *= "ref_tilt = $(String(bendP["tilt_ref"])),"
        end
        push_attr!(tmp)
      end
    elseif key == "BodyShiftP"
      bodyshiftP = props["BodyShiftP"]
      for bskey in keys(bodyshiftP)
        tmp = ""
        if bskey == "x_offset"
          tmp = "x_offset = $(String(bodyshiftP["x_offset"])),"
        elseif bskey == "y_offset"
          tmp = "y_offset = $(String(bodyshiftP["y_offset"])),"
        elseif bskey == "z_offset"
          tmp = "z_offset = $(String(bodyshiftP["z_offset"])),"
        elseif bskey == "x_rot"
          tmp = "y_pitch = $(-Float64(bodyshiftP["x_rot"])),"
        elseif bskey == "y_rot"
          tmp = "x_pitch = $(String(bodyshiftP["y_rot"])),"
        elseif bskey == "z_rot"
          tmp = "tilt = $(String(bodyshiftP["z_rot"])),"
        end
        push_attr!(tmp)
      end
    elseif key == "ElectricMultipoleP"
      error("ElectricMultipoleP not yet supported")
    elseif key == "FloorP"
      error("FloorP not yet supported")
    elseif key == "FloorShiftP"
      error("FloorShiftP not yet supported")
    elseif key == "ForkP"
      error("ForkP not yet supported")
    elseif key == "GirderP"
      error("GirderP not yet supported")
    elseif key == "MagneticMultipoleP"
      mmP  = props["MagneticMultipoleP"]

      full = FullRepresentation()
      full.L = haskey(props, "length") ? Float64(props["length"]) : 1.0

      _fill_multipoles!(full, mmP, node_key(ele[1]))

      if all(values(full.normalized))
        # push_attr!("field_master = F") # (Default)
      elseif all(!, values(full.normalized)) && ele_kind != "RFCavity"
        push_attr!("field_master = T")
      else
        error("$(node_key(props)): Multipoles of one element must be all normalized or all unnormalized.")
      end

      rep = _KindMap(ele_kind)(full)   # pick the element-specific representation, then down-convert
      append!(attrs, _mp_key(rep))

    elseif key == "MetaP"
      println("MetaP not supported in Bmad")
    elseif key == "PatchP"
      patchP = props["PatchP"]
      for pkey in keys(patchP)
        tmp = ""
        if pkey == "x_offset"
          tmp = "x_offset = $(String(patchP["x_offset"])),"
        elseif pkey == "y_offset"
          tmp = "y_offset = $(String(patchP["y_offset"])),"
        elseif pkey == "z_offset"
          tmp = "z_offset = $(String(patchP["z_offset"])),"
        elseif pkey == "t_offset"
          tmp = "t_offset = $(String(patchP["t_offset"])),"
        elseif pkey == "x_rot"
          tmp = "y_pitch = $(-Float64(patchP["x_rot"])),"
        elseif pkey == "y_rot"
          tmp = "x_pitch = $(String(patchP["y_rot"])),"
        elseif pkey == "z_rot"
          tmp = "tilt = $(String(patchP["z_rot"])),"
        elseif pkey == "flexible"
          flex = lowercase(String(patchP["flexible"]))
          tmp = "flexible = $(flex == "true" ? "T" : "F"),"
        elseif pkey == "ref_coords"
          ref = lowercase(String(apertureP["ref_coords"]))
          if ref == "entrance_end"
            tmp = "ref_coords = entrance_end,"
          elseif ref == "exit_end"
            tmp = "ref_coords = exit_end,"
          end
        elseif pkey == "user_sets_length"
          usl = lowercase(String(patchP["user_sets_length"]))
          tmp = "user_sets_length = $(usl == "true" ? "T" : "F"),"
        end
        push_attr!(tmp)
      end
    elseif key == "RFP"
      rfP = props["RFP"]
      if String(props["kind"]) == "CrabCavity"
        error("$(node_key(props)): CrabCavity not yet translated")
      end
      for rfkey in keys(rfP)
        tmp = ""
        if rfkey == "frequency"
          tmp *= "rf_frequency = $(String(rfP["frequency"])), "
          tmp *= "harmon_master = false,"

        elseif rfkey == "harmon"
          tmp *= "harmon = $(String(rfP["harmon"])), "
          tmp *= "harmon_master = true,"

        elseif rfkey == "voltage"
          tmp *= "voltage = $(String(rfP["voltage"])),"

        elseif rfkey == "gradient"
          if haskey(props, "L") && props["L"] != 0
            L = props["L"]
            grad = Float64(rfP["gradient"])
            tmp *= "voltage = $(grad*L),"
            println("$(node_key(props)): gradient not yet supported, replacing with voltage = gradient * length")
          else
            error("$(node_key(props)): `gradient` not yet supported & `length` is undefined => voltage is undefined")
          end

        elseif rfkey == "phase"
          tmp *= "phi0 = $(String(rfP["phase"])),"

        elseif rfkey == "multipass_phase"
          tmp *= "phi0_multipass = $(String(rfP["multipass_phase"])),"

        elseif rfkey == "cavity_type"
          tmp *= "cavity_type = $(String(rfP["cavity_type"])),"

        elseif rfkey == "num_cells"
          tmp *= "n_cell = $(String(rfP["num_cells"])),"

        elseif rfkey == "zero_phase"
          zp = String(rfP["zero_phase"])
          if zp == "ACCELERATING"
            error("$(node_key(props)): `Accelerating` phase is not supported with phi0_autoscale in Bmad")
          elseif zp == "BELOW_TRANSITION"
            tmp *= "rf_phase_below_transition_ref = T,"
          elseif zp == "ABOVE_TRANSITION"
            tmp *= "rf_phase_below_transition_ref = F,"
          else
            println("$(node_key(props)): unknown zero_phase type")
          end

        elseif rfkey == "L_active"
          error("$(node_key(props)): `L_active` is a dependent parameter in Bmad")

        elseif rfkey == "dE_ref"
          error("$(node_key(props)): needs translation to LCavity for `dE_ref`")
        end
        push_attr!(tmp)
      end
      if haskey(rfP, "frequency") && haskey(rfP, "harmon")
        error("$(node_key(props)): can only define `frequency` or `harmon` but not both")
      end
    elseif key == "SolenoidP"
      solP = props["SolenoidP"]
      if !isempty(keys(solP))
        if haskey(solP, "Ksol")
          push_attr!("ks = $(String(solP["Ksol"]))")
        elseif haskey(solP, "Bsol")
          push_attr!("field_master = T")
          push_attr!("bs_field = $(String(solP["Bsol"]))")
        else
          println("$(node_key(props)) - unknown key(s): $(keys(solP))")
        end
      end
    elseif key == "TrackingP"
      trackingP = props["TrackingP"]
      for tkey in keys(trackingP)
        if tkey == "Bmad"
        end
      end
    elseif key == "ReferenceChangeP"
      if ele_kind_bmad != "Patch"
        error("$(node_key(props)): Bmad reference changes only allowed in Patch elements (PALS: Patch / RefereneChange)")
      else
        refchangeP = props["ReferenceChangeP"]
        for rkey in keys(refchangeP)
          if rkey == "dtime_ref"
            push_attr!("t_offset = $(String(refchangeP["dtime_ref"]))")

          elseif rkey == "dE_ref"
            push_attr!("E_tot_offset = $(String(refchangeP["dE_ref"]))")

          elseif rkey == "dpc_ref"
            error("$(node_key(props)): dpc_ref (p0c_offset) not supported by Bmad, only E_tot_offset")

          elseif rkey == "time_ref"
            error("$(node_key(props)): setting time_ref is not supported by Bmad")

          elseif rkey == "E_tot_ref"
            push_attr!("E_tot_set = $(String(refchangeP["E_tot_ref"]))")

          elseif rkey == "pc_ref"
            push_attr!("p0c_set = $(String(refchangeP["pc_ref"]))")

          elseif rkey == "species_ref"
            error("$(node_key(props)): changing species in-beamline is not supported by Bmad")
          end
        end
      end
    end
  end

  return BmadEleDef(node_key(ele[1]), ele_kind_bmad, attrs)
end
