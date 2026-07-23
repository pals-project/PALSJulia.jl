"""
    SciBmadEle

A single SciBmad `LineElement`: its `name` and the already-translated keyword-argument
fragments (`attrs`, each a `"keyword = value"` string).
"""
struct SciBmadEle
  name::String
  attrs::Vector{String}
end

#---------------------------------------------------------------------------------------------------
"""
    SciBmadBeamline

A SciBmad `Beamline`: its `name`, the ordered member element `members` (by name), and the
reference-parameter fragments `ref` taken from the line's first entry.
"""
struct SciBmadBeamline
  name::String
  members::Vector{String}
  ref::Vector{String}
end

#---------------------------------------------------------------------------------------------------
"""
    SciBmadLatticeList

A SciBmad lattice list: its `name` and the ordered branch/beamline `branches` (by name).
"""
struct SciBmadLatticeList
  name::String
  branches::Vector{String}
end

#---------------------------------------------------------------------------------------------------
"""
    SciBmadLattice

An in-memory model of a SciBmad lattice.

Produced by [`pals_to_scibmad`](@ref) and serialized to a file by [`write_scibmad_file`](@ref):
  - `particle`  : `BeginningEle` particle-coordinate lines (including the `v = [...]` vector).
  - `elements`  : `LineElement` definitions ([`SciBmadEle`](@ref)).
  - `beamlines` : `Beamline` definitions ([`SciBmadBeamline`](@ref)).
  - `lattices`  : lattice lists ([`SciBmadLatticeList`](@ref)).
"""
struct SciBmadLattice
  particle::Vector{String}
  elements::Vector{SciBmadEle}
  beamlines::Vector{SciBmadBeamline}
  lattices::Vector{SciBmadLatticeList}
end
SciBmadLattice() = SciBmadLattice(String[], SciBmadEle[], SciBmadBeamline[], SciBmadLatticeList[])

#---------------------------------------------------------------------------------------------------
"""
    pals_to_scibmad(yaml::YAMLNode)

Translate a parsed PALS lattice `yaml` (as returned by [`parse_file`](@ref)) into a
[`SciBmadLattice`](@ref).

The returned structure is an in-memory model of the *SciBmad* lattice (elements, beamlines,
lattice lists), not the input PALS tree. Translation is a three-step process: parse the PALS
file with `parse_file`, build the target model with `pals_to_scibmad`, then emit the SciBmad
lattice file with [`write_scibmad_file`](@ref):

```julia
yaml = parse_file(file_dir)
write_scibmad_file(pals_to_scibmad(yaml), filename)
```
"""
function pals_to_scibmad(yaml::YAMLNode)
  facility = yaml["PALS"]["facility"]
  lat = SciBmadLattice()
  for ele in facility
    props = ele[keys(ele)[1]]
    haskey(props, "kind") || continue
    kind = String(props["kind"])
    if kind == "BeginningEle"
      _, particle = _ele_to_scibmad_str(ele)
      append!(lat.particle, particle)
    elseif kind == "Lattice"
      name = String(keys(ele)[1])
      branches = String[]
      for bl in props["branches"]
        push!(branches, String(bl))
      end
      push!(lat.lattices, SciBmadLatticeList(name, branches))
    elseif kind == "BeamLine"
      push!(lat.beamlines, _make_scibmad_beamline(ele))
    else
      push!(lat.elements, _make_scibmad_ele(ele))
    end
  end
  return lat
end

#---------------------------------------------------------------------------------------------------
"""
    write_scibmad_file(lat::SciBmadLattice, filename::String)

Serialize the [`SciBmadLattice`](@ref) `lat` to `filename` as a SciBmad lattice file.

Write the particle-start block, the `@elements` block of `LineElement`s, the `Beamline`
definitions, and the lattice lists.
"""
function write_scibmad_file(lat::SciBmadLattice, filename::String)
  open(filename, "w") do io
    if !isempty(lat.particle)
      write(io, join(lat.particle, "\n") * "\n\n")
    end
    write(io, "@elements begin\n")
    for ele in lat.elements
      write(io, _format_scibmad_ele(ele) * "\n")
    end
    write(io, "end\n\n")
    for bl in lat.beamlines
      write(io, _format_scibmad_beamline(bl) * "\n")
    end
    for latt in lat.lattices
      write(io, _format_scibmad_lattice(latt) * "\n")
    end
  end
  return nothing
end

#---------------------------------------------------------------------------------------------------
"""
    _format_scibmad_ele(ele::SciBmadEle)

Render a [`SciBmadEle`](@ref) as a `name = LineElement(...)` definition.
"""
function _format_scibmad_ele(ele::SciBmadEle)
  return "$(ele.name) = LineElement($(join(ele.attrs, ", ")))"
end

#---------------------------------------------------------------------------------------------------
"""
    _format_scibmad_beamline(bl::SciBmadBeamline)

Render a [`SciBmadBeamline`](@ref) as a `name = Beamline([members], ref...)` definition.
"""
function _format_scibmad_beamline(bl::SciBmadBeamline)
  members = join([m * "," for m in bl.members])
  ref     = join([r * "," for r in bl.ref])
  return "$(bl.name) = Beamline([$members], $ref)"
end

#---------------------------------------------------------------------------------------------------
"""
    _format_scibmad_lattice(latt::SciBmadLatticeList)

Render a [`SciBmadLatticeList`](@ref) as a `name = [branches]` list.
"""
function _format_scibmad_lattice(latt::SciBmadLatticeList)
  inner = join([b * "," for b in latt.branches])
  return "$(latt.name) = [$inner]"
end

#---------------------------------------------------------------------------------------------------
"""
    _ele_to_scibmad_str(ele::YAMLNode)

Translate a `BeginningEle` element into SciBmad reference and particle fragments.

Return `(ref, particle)` where `ref` holds the reference-parameter fragments from the element's
`ReferenceP` (species and energy) and `particle` holds the coordinate lines from its `ParticleP`
(followed by the `v = [...]` phase-space vector).
"""
function _ele_to_scibmad_str(ele::YAMLNode)
  props = ele[keys(ele)[1]]
  ref = String[]
  particle = String[]
  for key in keys(props)
    if key == "ReferenceP"
      referenceP = props["ReferenceP"]
      for k in keys(referenceP)
        if k == "species_ref"
          push!(ref, "species_ref = $(String(referenceP[k]))")
        elseif k == "pc_ref"
          push!(ref, "pc_ref = $(String(referenceP[k]))")
        elseif k == "E_tot_ref"
          push!(ref, "E_ref = $(String(referenceP[k]))")
        elseif k == "time_ref" || k == "location"
          println("$k not supported yet")
        end
      end
    elseif key == "ParticleP"
      particleP = props["ParticleP"]
      for k in keys(particleP)
        val = String(particleP[k])
        if k == "x"
          push!(particle, "x = $val")
        elseif k == "y"
          push!(particle, "y = $val")
        elseif k == "z"
          push!(particle, "z = $val")
        elseif k == "px"
          push!(particle, "px = $val")
        elseif k == "py"
          push!(particle, "py = $val")
        elseif k == "pz"
          push!(particle, "pz = $val")
        end
      end
      push!(particle, "v = [ x px y py z pz ]")
    end
  end
  return ref, particle
end

#---------------------------------------------------------------------------------------------------
"""
    _make_scibmad_beamline(ele::YAMLNode)

Translate a `BeamLine` element into a [`SciBmadBeamline`](@ref).

Collect the member element names (dropping the leading reference entry, `line[1]`) and the
reference parameters read from that first entry.
"""
function _make_scibmad_beamline(ele::YAMLNode)
  name = String(keys(ele)[1])
  props = ele[keys(ele)[1]]
  line = props["line"]
  ref, _ = _ele_to_scibmad_str(line[1])
  members = String[]
  for i in 2:length(line)
    line_ele = line[i]
    if is_scalar(line_ele)
      push!(members, String(line_ele))
    elseif is_map(line_ele)
      push!(members, String(keys(line_ele)[1]))
    end
  end
  return SciBmadBeamline(name, members, ref)
end

#---------------------------------------------------------------------------------------------------
"""
    _make_scibmad_ele(ele::YAMLNode)

Translate a single PALS element into a [`SciBmadEle`](@ref).

Dispatch on the element's parameter groups (aperture, bend, body shift, multipoles, patch,
RF, solenoid, tracking, reference change, ...) to build the keyword-argument fragments of a
`LineElement`. Unsupported parameters emit a message.
"""
function _make_scibmad_ele(ele::YAMLNode)
  props = ele[keys(ele)[1]]
  attrs = String[]

  for key in keys(props)
    if key == "kind"
      push!(attrs, "kind = $(String(props["kind"]))")
    elseif key == "length"
      push!(attrs, "L = $(String(props["length"]))")
    elseif key == "ACKickerP"
      println("ACKickerP not yet supported")
    elseif key == "ApertureP"
      apertureP = props["ApertureP"]
      has_xmin   = haskey(apertureP, "x_min");   has_xmax  = haskey(apertureP, "x_max")
      has_xwidth = haskey(apertureP, "x_width");  has_xcen  = haskey(apertureP, "x_center")
      if (has_xmin || has_xmax) && (has_xwidth || has_xcen)
        println("Either min and max should be defined or width and center, not both.")
      elseif (has_xmin && !has_xmax) || (has_xmax && !has_xmin)
        println("Both min and max need to be defined.")
      elseif has_xmin && has_xmax
        push!(attrs, "x1_limit = $(String(apertureP["x_min"]))")
        push!(attrs, "x2_limit = $(String(apertureP["x_max"]))")
      elseif (has_xwidth && !has_xcen) || (has_xcen && !has_xwidth)
        println("Both width and center need to be defined.")
      else
        width  = Float64(apertureP["x_width"])
        center = Float64(apertureP["x_center"])
        push!(attrs, "x1_limit = $(center - width / 2)")
        push!(attrs, "x2_limit = $(center + width / 2)")
      end
      has_ymin   = haskey(apertureP, "y_min");   has_ymax  = haskey(apertureP, "y_max")
      has_ywidth = haskey(apertureP, "y_width");  has_ycen  = haskey(apertureP, "y_center")
      if (has_ymin || has_ymax) && (has_ywidth || has_ycen)
        println("Either min and max should be defined or width and center, not both.")
      elseif (has_ymin && !has_ymax) || (has_ymax && !has_ymin)
        println("Both min and max need to be defined.")
      elseif has_ymin && has_ymax
        push!(attrs, "y1_limit = $(String(apertureP["y_min"]))")
        push!(attrs, "y2_limit = $(String(apertureP["y_max"]))")
      elseif (has_ywidth && !has_ycen) || (has_ycen && !has_ywidth)
        println("Both width and center need to be defined.")
      else
        width  = Float64(apertureP["y_width"])
        center = Float64(apertureP["y_center"])
        push!(attrs, "y1_limit = $(center - width / 2)")
        push!(attrs, "y2_limit = $(center + width / 2)")
      end
      for akey in keys(apertureP)
        if akey == "shape"
          shape = String(apertureP["shape"])
          if shape == "ELLIPTICAL"
            push!(attrs, "aperture_shape = ApertureShape.Elliptical")
          elseif shape == "RECTANGULAR"
            push!(attrs, "aperture_shape = ApertureShape.Rectangular")
          else
            println("shape $shape is not supported")
          end
        elseif akey == "location"
          location = String(apertureP["location"])
          if location == "ENTRANCE_END"
            push!(attrs, "aperture_at = ApertureAt.Entrance")
          elseif location == "EXIT_END"
            push!(attrs, "aperture_at = ApertureAt.Exit")
          elseif location == "BOTH_ENDS"
            push!(attrs, "aperture_at = ApertureAt.BothEnds")
          elseif location == "EVERYWHERE" || location == "CENTER"
            push!(attrs, "aperture_at = ApertureAt.BothEnds")
            println("location $location not supported, set to BothEnds")
          elseif location == "NOWHERE"
            println("location $location not supported")
          end
        elseif akey == "aperture_shifts_with_body"
          shifts = lowercase(String(apertureP["aperture_shifts_with_body"]))
          push!(attrs, "aperture_shifts_with_body = $(shifts == "true")")
        elseif akey == "aperture_active"
          active = lowercase(String(apertureP["aperture_active"]))
          push!(attrs, "aperture_active = $(active == "true")")
        elseif akey == "vertices"
          println("vertices not yet supported")
        elseif akey == "material"
          println("material not yet supported")
        elseif akey == "thickness"
          println("thickness not yet supported")
        end
      end
    elseif key == "BeamBeamP"
      bbP = props["BeamBeamP"]
      for bbkey in keys(bbP)
        if bbkey in ("sigma_x", "sigma_y", "sigma_z", "alpha_x", "beta_x",
                     "alpha_y", "beta_y", "charge", "energy", "N_particle")
          push!(attrs, "$bbkey = $(String(bbP[bbkey]))")
        end
      end
    elseif key == "BendP"
      bendP = props["BendP"]
      for bkey in keys(bendP)
        if bkey == "radius_ref"
          println("radius_ref not yet supported")
        elseif bkey == "Bn0_ref"
          println("Bn0_ref not yet supported")
        elseif bkey == "e1"
          push!(attrs, "e1 = $(String(bendP["e1"]))")
        elseif bkey == "e2"
          push!(attrs, "e2 = $(String(bendP["e2"]))")
        elseif bkey == "e1_rect"
          println("e1_rect not yet supported")
        elseif bkey == "e2_rect"
          println("e2_rect not yet supported")
        elseif bkey == "edge1_int"
          push!(attrs, "edge1_int = $(String(bendP["edge1_int"]))")
        elseif bkey == "edge2_int"
          push!(attrs, "edge2_int = $(String(bendP["edge2_int"]))")
        elseif bkey == "g_ref"
          push!(attrs, "g_ref = $(String(bendP["g_ref"]))")
        elseif bkey == "h1"
          println("h1 not yet supported")
        elseif bkey == "h2"
          println("h2 not yet supported")
        elseif bkey == "L_chord"
          println("L_chord not yet supported")
        elseif bkey == "L_sagitta"
          println("L_sagitta not yet supported")
        elseif bkey == "tilt_ref"
          push!(attrs, "tilt_ref = $(String(bendP["tilt_ref"]))")
        end
      end
    elseif key == "BodyShiftP"
      bodyshiftP = props["BodyShiftP"]
      for bskey in keys(bodyshiftP)
        if bskey == "x_offset"
          push!(attrs, "x_offset = $(String(bodyshiftP["x_offset"]))")
        elseif bskey == "y_offset"
          push!(attrs, "y_offset = $(String(bodyshiftP["y_offset"]))")
        elseif bskey == "z_offset"
          push!(attrs, "z_offset = $(String(bodyshiftP["z_offset"]))")
        elseif bskey == "x_rot"
          push!(attrs, "x_rot = $(String(bodyshiftP["x_rot"]))")
        elseif bskey == "y_rot"
          push!(attrs, "y_rot = $(String(bodyshiftP["y_rot"]))")
        elseif bskey == "z_rot"
          push!(attrs, "tilt = $(String(bodyshiftP["z_rot"]))")
        end
      end
    elseif key == "ElectricMultipoleP"
      println("ElectricMultipoleP not yet supported")
    elseif key == "FloorP"
      println("FloorP not yet supported")
    elseif key == "FloorShiftP"
      println("FloorShiftP not yet supported")
    elseif key == "ForkP"
      println("ForkP not yet supported")
    elseif key == "GirderP"
      println("GirderP not yet supported")
    elseif key == "MagneticMultipoleP"
      mmP = props["MagneticMultipoleP"]
      for mmkey in keys(mmP)
        push!(attrs, "$mmkey = $(String(mmP[mmkey]))")
      end
    elseif key == "MetaP"
      metaP = props["MetaP"]
      for mkey in keys(metaP)
        if mkey == "alias"
          push!(attrs, "alias = $(String(metaP["alias"]))")
        elseif mkey == "label"
          push!(attrs, "label = $(String(metaP["label"]))")
        elseif mkey == "description"
          push!(attrs, "description = $(String(metaP["description"]))")
        end
      end
      println("MetaP not yet supported")
    elseif key == "PatchP"
      patchP = props["PatchP"]
      for pkey in keys(patchP)
        if pkey == "x_offset"
          push!(attrs, "dx = $(String(patchP["x_offset"]))")
        elseif pkey == "y_offset"
          push!(attrs, "dy = $(String(patchP["y_offset"]))")
        elseif pkey == "z_offset"
          push!(attrs, "dz = $(String(patchP["z_offset"]))")
        elseif pkey == "t_offset"
          push!(attrs, "dt = $(String(patchP["t_offset"]))")
        elseif pkey == "x_rot"
          push!(attrs, "dx_rot = $(String(patchP["x_rot"]))")
        elseif pkey == "y_rot"
          push!(attrs, "dy_rot = $(String(patchP["y_rot"]))")
        elseif pkey == "z_rot"
          push!(attrs, "dz_rot = $(String(patchP["z_rot"]))")
        elseif pkey == "flexible"
          println("flexible not yet supported")
        elseif pkey == "ref_coords"
          println("ref_coords not yet supported")
        elseif pkey == "user_sets_length"
          println("user_sets_length not yet supported")
        end
      end
    elseif key == "RFP"
      rfP = props["RFP"]
      if String(props["kind"]) == "CrabCavity"
        push!(attrs, "is_crabcavity = true")
      end
      num_cells = 0
      L_active  = 0.0
      for rfkey in keys(rfP)
        if rfkey == "frequency"
          push!(attrs, "rate = $(String(rfP["frequency"]))")
          push!(attrs, "rate_meaning = false")
        elseif rfkey == "harmon"
          push!(attrs, "rate = $(String(rfP["harmon"]))")
          push!(attrs, "rate_meaning = true")
        elseif rfkey == "voltage"
          push!(attrs, "voltage = $(String(rfP["voltage"]))")
        elseif rfkey == "gradient"
          println("gradient not yet supported")
        elseif rfkey == "phase"
          push!(attrs, "phi0 = $(2 * π * Float64(rfP["phase"]))")
        elseif rfkey == "multipass_phase"
          println("multipass_phase not yet supported")
        elseif rfkey == "cavity_type"
          push!(attrs, "traveling_wave = $(String(rfP["cavity_type"]) == "TRAVELING_WAVE")")
        elseif rfkey == "num_cells"
          num_cells = Int(rfP["num_cells"])
        elseif rfkey == "L_active"
          L_active = Float64(rfP["L_active"])
        elseif rfkey == "zero_phase"
          zp = String(rfP["zero_phase"])
          if zp == "ACCELERATING"
            push!(attrs, "zero_phase = Accelerating")
          elseif zp == "BELOW_TRANSITION"
            push!(attrs, "zero_phase = BelowTransition")
          elseif zp == "ABOVE_TRANSITION"
            push!(attrs, "zero_phase = AboveTransition")
          end
        end
      end
      if !haskey(rfP, "frequency") && !haskey(rfP, "harmon")
        push!(attrs, "rate_meaning = -1")
      end
      push!(attrs, "tracking_method = SaganCavity(num_cells = $num_cells, L_active = $L_active)")
    elseif key == "SolenoidP"
      solP = props["SolenoidP"]
      for skey in keys(solP)
        push!(attrs, "$skey = $(String(solP[skey]))")
      end
    elseif key == "TrackingP"
      trackingP = props["TrackingP"]
      for tkey in keys(trackingP)
        if tkey == "SciBmad"
          sbm = trackingP["SciBmad"]
          for sbkey in keys(sbm)
            if sbkey == "tracking_method"
              if String(sbm["tracking_method"]) == "scibmad_standard"
                push!(attrs, "tracking_method = SciBmadStandard()")
              end
            end
          end
        end
      end
    elseif key == "ReferenceChangeP"
      refchangeP = props["ReferenceChangeP"]
      for rkey in keys(refchangeP)
        if rkey == "extra_dtime_ref"
          println("extra_dtime_ref not yet supported")
        elseif rkey == "dE_ref"
          push!(attrs, "dE_ref = $(String(refchangeP["dE_ref"]))")
        elseif rkey == "E_tot_ref"
          push!(attrs, "E_ref = $(String(refchangeP["E_tot_ref"]))")
        elseif rkey == "species_ref"
          push!(attrs, "species_ref = $(String(refchangeP["species_ref"]))")
        end
      end
    end
  end

  return SciBmadEle(String(keys(ele)[1]), attrs)
end
