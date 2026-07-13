"""
    pals_to_scibmad(file_dir::String)

Read the PALS-YAML lattice file at `file_dir` and return its parsed YAML structure.

Pass the returned structure to [`write_scibmad_file`](@ref) to emit a SciBmad lattice file;
`write_scibmad_file(pals_to_scibmad(file_dir), filename)` reproduces the former
`toSciBmad(file_dir)`.
"""
function pals_to_scibmad(file_dir::String)
  return parse_file(file_dir)
end

#---------------------------------------------------------------------------------------------------
"""
    write_scibmad_file(yaml::YAMLNode, filename::String)

Write the SciBmad lattice described by the PALS `yaml` structure to `filename`.

Walk the `PALS/facility` element list of `yaml` and write the corresponding SciBmad description:
an `@elements` block of `LineElement`s, the `Beamline` definitions, and the lattice list.
"""
function write_scibmad_file(yaml::YAMLNode, filename::String)
  facility = yaml["PALS"]["facility"]
  open(filename, "w") do io
    ele_str     = ""
    bl_str      = ""
    lattice_str = ""
    for ele in facility
      props = ele[keys(ele)[1]]
      if haskey(props, "kind")
        kind = String(props["kind"])
        if kind == "BeginningEle"
          _, particle_str = _ele_to_scibmad_str(ele)
          write(io, particle_str * "\n\n")
        elseif kind == "Lattice"
          latticees = props["branches"]
          for bl in latticees
            lattice_str *= "$(String(bl)),"
          end
          name        = keys(ele)[1]
          # placeholder for when Lattice element in SciBmad is implemented
          lattice_str = "$name = [$lattice_str]"
        elseif kind == "BeamLine"
          bl_str *= _make_beamline_str(ele) * "\n"
        else
          ele_str *= _make_scibmad_ele_str(ele) * "\n"
        end
      end
    end
    write(io, "@elements begin\n$(ele_str)end\n\n")
    write(io, bl_str)
    write(io, lattice_str)
  end
end

#---------------------------------------------------------------------------------------------------
"""
    _ele_to_scibmad_str(ele::YAMLNode)

Translate a `BeginningEle` element into SciBmad reference and particle strings.

Return `(ref_str, particle_str)` built from the element's `ReferenceP` (species and energy)
and `ParticleP` (initial coordinates and the `v = [...]` vector).
"""
function _ele_to_scibmad_str(ele::YAMLNode)
  props = ele[keys(ele)[1]]
  ref_str, particle_str = "", ""
  for key in keys(props)
    if key == "ReferenceP"
      referenceP = props["ReferenceP"]
      ref_str = ""
      for k in keys(referenceP)
        if k == "species_ref"
          ref_str *= "species_ref = $(String(referenceP[k])),"
        elseif k == "pc_ref"
          ref_str *= "pc_ref = $(String(referenceP[k])),"
        elseif k == "E_tot_ref"
          ref_str *= "E_ref = $(String(referenceP[k])),"
        elseif k == "time_ref" || k == "location"
          println("$k not supported yet")
        end
      end
    elseif key == "ParticleP"
      println("particle")
      particleP = props["ParticleP"]
      particle_str = ""
      for k in keys(particleP)
        val = String(particleP[k])
        if k == "x"
          particle_str *= "x = $val\n"
        elseif k == "y"
          particle_str *= "y = $val\n"
        elseif k == "z"
          particle_str *= "z = $val\n"
        elseif k == "px"
          particle_str *= "px = $val\n"
        elseif k == "py"
          particle_str *= "py = $val\n"
        elseif k == "pz"
          particle_str *= "pz = $val\n"
        end
      end
      particle_str *= "v = [ x px y py z pz ]"
    end
  end
  return ref_str, particle_str
end

#---------------------------------------------------------------------------------------------------
"""
    _make_beamline_str(ele::YAMLNode)

Build a SciBmad `Beamline([...], ref)` definition for a `BeamLine` element.

List each member element by name and prepend the reference parameters from the line's first
entry.
"""
function _make_beamline_str(ele::YAMLNode)
  props = ele[keys(ele)[1]]
  line = props["line"]
  line_str = ""
  ref_str, _ = _ele_to_scibmad_str(line[1])
  for i in 2:length(line)
    line_ele = line[i]
    if is_scalar(line_ele)
      line_str *= "$(String(line_ele)),"
    elseif is_map(line_ele)
      name = keys(line_ele)[1]
      line_str *= "$name,"
    end
  end
  return "$(keys(ele)[1]) = Beamline([$line_str], $ref_str)"
end

#---------------------------------------------------------------------------------------------------
"""
    _make_scibmad_ele_str(ele::YAMLNode)

Translate a single PALS element into a SciBmad `LineElement(...)` string.

Dispatch on the element's parameter groups (aperture, bend, body shift, multipoles, patch,
RF, solenoid, tracking, reference change, ...) to build the keyword arguments of a
`name = LineElement(...)` definition. Unsupported parameters emit a message.
"""
function _make_scibmad_ele_str(ele::YAMLNode)
  props = ele[keys(ele)[1]]
  paramString = ""

  for key in keys(props)
    if key == "kind"
      paramString *= "kind = $(String(props["kind"])),"
    elseif key == "length"
      paramString *= "L = $(String(props["length"])),"
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
        paramString *= "x1_limit = $(String(apertureP["x_min"])),"
        paramString *= "x2_limit = $(String(apertureP["x_max"])),"
      elseif (has_xwidth && !has_xcen) || (has_xcen && !has_xwidth)
        println("Both width and center need to be defined.")
      else
        width  = Float64(apertureP["x_width"])
        center = Float64(apertureP["x_center"])
        paramString *= "x1_limit = $(center - width / 2),"
        paramString *= "x2_limit = $(center + width / 2),"
      end
      has_ymin   = haskey(apertureP, "y_min");   has_ymax  = haskey(apertureP, "y_max")
      has_ywidth = haskey(apertureP, "y_width");  has_ycen  = haskey(apertureP, "y_center")
      if (has_ymin || has_ymax) && (has_ywidth || has_ycen)
        println("Either min and max should be defined or width and center, not both.")
      elseif (has_ymin && !has_ymax) || (has_ymax && !has_ymin)
        println("Both min and max need to be defined.")
      elseif has_ymin && has_ymax
        paramString *= "y1_limit = $(String(apertureP["y_min"])),"
        paramString *= "y2_limit = $(String(apertureP["y_max"])),"
      elseif (has_ywidth && !has_ycen) || (has_ycen && !has_ywidth)
        println("Both width and center need to be defined.")
      else
        width  = Float64(apertureP["y_width"])
        center = Float64(apertureP["y_center"])
        paramString *= "y1_limit = $(center - width / 2),"
        paramString *= "y2_limit = $(center + width / 2),"
      end
      for akey in keys(apertureP)
        if akey == "shape"
          shape = String(apertureP["shape"])
          if shape == "ELLIPTICAL"
            paramString *= "aperture_shape = ApertureShape.Elliptical,"
          elseif shape == "RECTANGULAR"
            paramString *= "aperture_shape = ApertureShape.Rectangular,"
          else
            println("shape $shape is not supported")
          end
        elseif akey == "location"
          location = String(apertureP["location"])
          if location == "ENTRANCE_END"
            paramString *= "aperture_at = ApertureAt.Entrance,"
          elseif location == "EXIT_END"
            paramString *= "aperture_at = ApertureAt.Exit,"
          elseif location == "BOTH_ENDS"
            paramString *= "aperture_at = ApertureAt.BothEnds,"
          elseif location == "EVERYWHERE" || location == "CENTER"
            paramString *= "aperture_at = ApertureAt.BothEnds,"
            println("location $location not supported, set to BothEnds")
          elseif location == "NOWHERE"
            println("location $location not supported")
          end
        elseif akey == "aperture_shifts_with_body"
          shifts = lowercase(String(apertureP["aperture_shifts_with_body"]))
          paramString *= "aperture_shifts_with_body = $(shifts == "true"),"
        elseif akey == "aperture_active"
          active = lowercase(String(apertureP["aperture_active"]))
          paramString *= "aperture_active = $(active == "true"),"
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
        if bbkey == "sigma_x"
          paramString *= "$bbkey = $(String(bbP[bbkey])),"
        elseif bbkey == "sigma_y"
          paramString *= "$bbkey = $(String(bbP[bbkey])),"
        elseif bbkey == "sigma_z"
          paramString *= "$bbkey = $(String(bbP[bbkey])),"
        elseif bbkey == "alpha_x"
          paramString *= "$bbkey = $(String(bbP[bbkey])),"
        elseif bbkey == "beta_x"
          paramString *= "$bbkey = $(String(bbP[bbkey])),"
        elseif bbkey == "alpha_y"
          paramString *= "$bbkey = $(String(bbP[bbkey])),"
        elseif bbkey == "beta_y"
          paramString *= "$bbkey = $(String(bbP[bbkey])),"
        elseif bbkey == "charge"
          paramString *= "$bbkey = $(String(bbP[bbkey])),"
        elseif bbkey == "energy"
          paramString *= "$bbkey = $(String(bbP[bbkey])),"
        elseif bbkey == "N_particle"
          paramString *= "$bbkey = $(String(bbP[bbkey])),"
        end
      end
    elseif key == "BendP"
      bendP = props["BendP"]
      for bkey in keys(bendP)
        if bkey == "rho_ref"
          println("rho_ref not yet supported")
        elseif bkey == "bend_field_ref"
          println("bend_field_ref not yet supported")
        elseif bkey == "e1"
          paramString *= "e1 = $(String(bendP["e1"])),"
        elseif bkey == "e2"
          paramString *= "e2 = $(String(bendP["e2"])),"
        elseif bkey == "e1_rect"
          println("e1_rect not yet supported")
        elseif bkey == "e2_rect"
          println("e2_rect not yet supported")
        elseif bkey == "edge1_int"
          paramString *= "edge1_int = $(String(bendP["edge1_int"])),"
        elseif bkey == "edge2_int"
          paramString *= "edge2_int = $(String(bendP["edge2_int"])),"
        elseif bkey == "g_ref"
          paramString *= "g_ref = $(String(bendP["g_ref"])),"
        elseif bkey == "h1"
          println("h1 not yet supported")
        elseif bkey == "h2"
          println("h2 not yet supported")
        elseif bkey == "L_chord"
          println("L_chord not yet supported")
        elseif bkey == "L_sagitta"
          println("L_sagitta not yet supported")
        elseif bkey == "tilt_ref"
          paramString *= "tilt_ref = $(String(bendP["tilt_ref"])),"
        end
      end
    elseif key == "BodyShiftP"
      bodyshiftP = props["BodyShiftP"]
      for bskey in keys(bodyshiftP)
        if bskey == "x_offset"
          paramString *= "x_offset = $(String(bodyshiftP["x_offset"])),"
        elseif bskey == "y_offset"
          paramString *= "y_offset = $(String(bodyshiftP["y_offset"])),"
        elseif bskey == "z_offset"
          paramString *= "z_offset = $(String(bodyshiftP["z_offset"])),"
        elseif bskey == "x_rot"
          paramString *= "x_rot = $(String(bodyshiftP["x_rot"])),"
        elseif bskey == "y_rot"
          paramString *= "y_rot = $(String(bodyshiftP["y_rot"])),"
        elseif bskey == "z_rot"
          paramString *= "tilt = $(String(bodyshiftP["z_rot"])),"
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
        paramString *= "$mmkey = $(String(mmP[mmkey])),"
      end
    elseif key == "MetaP"
      metaP = props["MetaP"]
      for mkey in keys(metaP)
        if mkey == "alias"
          paramString *= "alias = $(String(metaP["alias"])),"
        elseif mkey == "label"
          paramString *= "label = $(String(metaP["label"])),"
        elseif mkey == "description"
          paramString *= "description = $(String(metaP["description"])),"
        end
      end
      println("MetaP not yet supported")
    elseif key == "PatchP"
      patchP = props["PatchP"]
      for pkey in keys(patchP)
        if pkey == "x_offset"
          paramString *= "dx = $(String(patchP["x_offset"])),"
        elseif pkey == "y_offset"
          paramString *= "dy = $(String(patchP["y_offset"])),"
        elseif pkey == "z_offset"
          paramString *= "dz = $(String(patchP["z_offset"])),"
        elseif pkey == "t_offset"
          paramString *= "dt = $(String(patchP["t_offset"])),"
        elseif pkey == "x_rot"
          paramString *= "dx_rot = $(String(patchP["x_rot"])),"
        elseif pkey == "y_rot"
          paramString *= "dy_rot = $(String(patchP["y_rot"])),"
        elseif pkey == "z_rot"
          paramString *= "dz_rot = $(String(patchP["z_rot"])),"
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
        paramString *= "is_crabcavity = true,"
      end
      num_cells = 0
      L_active  = 0.0
      for rfkey in keys(rfP)
        if rfkey == "frequency"
          paramString *= "rate = $(String(rfP["frequency"])),"
          paramString *= "rate_meaning = false,"
        elseif rfkey == "harmon"
          paramString *= "rate = $(String(rfP["harmon"])),"
          paramString *= "rate_meaning = true,"
        elseif rfkey == "voltage"
          paramString *= "voltage = $(String(rfP["voltage"])),"
        elseif rfkey == "gradient"
          println("gradient not yet supported")
        elseif rfkey == "phase"
          paramString *= "phi0 = $(2 * π * Float64(rfP["phase"])),"
        elseif rfkey == "multipass_phase"
          println("multipass_phase not yet supported")
        elseif rfkey == "cavity_type"
          paramString *= "traveling_wave = $(String(rfP["cavity_type"]) == "TRAVELING_WAVE"),"
        elseif rfkey == "num_cells"
          num_cells = Int(rfP["num_cells"])
        elseif rfkey == "L_active"
          L_active = Float64(rfP["L_active"])
        elseif rfkey == "zero_phase"
          zp = String(rfP["zero_phase"])
          if zp == "ACCELERATING"
            paramString *= "zero_phase = Accelerating,"
          elseif zp == "BELOW_TRANSITION"
            paramString *= "zero_phase = BelowTransition,"
          elseif zp == "ABOVE_TRANSITION"
            paramString *= "zero_phase = AboveTransition,"
          end
        end
      end
      if !haskey(rfP, "frequency") && !haskey(rfP, "harmon")
        paramString *= "rate_meaning = -1,"
      end
      paramString *= "tracking_method = SaganCavity(num_cells = $num_cells, L_active = $L_active),"
    elseif key == "SolenoidP"
      solP = props["SolenoidP"]
      for skey in keys(solP)
        paramString *= "$skey = $(String(solP[skey])),"
      end
    elseif key == "TrackingP"
      trackingP = props["TrackingP"]
      for tkey in keys(trackingP)
        if tkey == "SciBmad"
          sbm = trackingP["SciBmad"]
          for sbkey in keys(sbm)
            if sbkey == "tracking_method"
              if String(sbm["tracking_method"]) == "scibmad_standard"
                paramString *= "tracking_method = SciBmadStandard(),"
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
          paramString *= "dE_ref = $(String(refchangeP["dE_ref"])),"
        elseif rkey == "E_tot_ref"
          paramString *= "E_ref = $(String(refchangeP["E_tot_ref"])),"
        elseif rkey == "species_ref"
          paramString *= "species_ref = $(String(refchangeP["species_ref"])),"
        end
      end
    end
  end

  return "$(keys(ele)[1]) = LineElement($paramString)"
end
