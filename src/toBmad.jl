import Pkg
Pkg.activate(joinpath(@__DIR__, ".."))
import PALSJulia as pj

function make_init_str(ele::pj.YAMLNode)
    props = ele[1]
    ref_str, particle_str = "", ""
    for key in keys(props)
        if key == "ReferenceP"
            println("Translating reference species and energy")
            referenceP = props["ReferenceP"]
            _keys = keys(referenceP)
            isempty(_keys) && continue
            for k in _keys
                if k == "species_ref"
                    ref_str *= "parameter[particle] = $(String(referenceP[k]))\n"
                elseif k == "pc_ref"
                    ref_str *= "parameter[p0c] = $(String(referenceP[k]))\n"
                elseif k == "E_tot_ref"
                    ref_str *= "parameter[E_tot] = $(String(referenceP[k]))\n"
                elseif k == "time_ref" || k == "location"
                    println("$k not supported yet")
                end
            end
        elseif key == "ParticleP"
            println("Translating particle init")
            particleP = props["ParticleP"]
            _keys = keys(particleP)
            isempty(_keys) && continue
            for k in _keys
                val = String(particleP[k])
                if k == "x"
                    particle_str *= "particle_start[x] = $val\n"
                elseif k == "y"
                    particle_str *= "particle_start[y] = $val\n"
                elseif k == "z"
                    particle_str *= "particle_start[z] = $val\n"
                elseif k == "px"
                    particle_str *= "particle_start[px] = $val\n"
                elseif k == "py"
                    particle_str *= "particle_start[py] = $val\n"
                elseif k == "pz"
                    particle_str *= "particle_start[pz] = $val\n"
                end
            end
        end
    end
    return ref_str, particle_str
end

function make_bl_str(ele::pj.YAMLNode)
    props = ele[1]
    line = props["line"]
    l_line = length(line)
    line_str = ""
    tmp = ""
    l_tmp = length(pj.node_key(props)) + 4

    for i in 2:l_line
        line_ele = line[i]

        if pj.is_scalar(line_ele)
            ele_str = "$(String(line_ele))"
        elseif pj.is_map(line_ele) || pj.is_sequence(line_ele)
            ele_str = pj.node_key(line_ele[1])
        else
            error("BeamLine $(pj.node_key(ele[1])) element $i is not scalar or sequence or map")
        end

        i < l_line && (ele_str *= ", ")
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
    return line_str
end

function bmad_kind(ele_kind::String)
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

abstract type MultipoleRepresentation end

# Raw, over-parametrized form: filled directly from PALS-YAML, then down-converted to
# whichever element-specific representation the element kind requires.
mutable struct FullRepresentation <: MultipoleRepresentation
    normalized::Dict{Int,Bool}
    integrated::Dict{Int,Bool}
    magnitude ::Dict{Int,Vector{Float64}}
    tilt      ::Dict{Int,Float64}
    L         ::Float64
end
FullRepresentation() = FullRepresentation(Dict(), Dict(), Dict(), Dict(), 1.0)
FullRepresentation(full::FullRepresentation) = full   # identity down-convert

# Element-specific form: only the final A/B field integrals.
struct ABRepresentation <: MultipoleRepresentation
    A::Dict{Int,Float64}
    B::Dict{Int,Float64}
end

# Down-convert the raw form to A/B field integrals.
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

# Selection layer: ele_kind -> the specific representation type it uses.
function KindMap(ele_kind)
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

# Filling layer: parse raw multipole data into the FullRepresentation slots.
function fill_multipoles!(full::FullRepresentation, mmP, name)
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

# Emission layer: each representation builds its own eleString fragment.
function mp_key(rep::ABRepresentation)
    mpString = ""
    _keys = keys(rep.A)
    isempty(_keys) && return mpString
    for mp in keys(rep.A)
        if !(rep.A[mp] ≈ 0)
            mpString *= "\tA$mp = $(rep.A[mp]),\n"
        end
        if !(rep.B[mp] ≈ 0)
            mpString *= "\tB$mp = $(rep.B[mp]),\n"
        end
    end
    return mpString
end

function mp_key(rep::FullRepresentation)
    mpString = ""
    _keys = keys(rep.normalized)
    isempty(_keys) && return mpString
    for mp in _keys
        val = rep.integrated[mp] ? rep.magnitude[mp][1] : rep.magnitude[mp][1] * rep.L
        mpString *= "\tKn$(mp)L = $val,\n"
        if rep.magnitude[mp][2] != 0
            mpString *= "\tKn$(mp)SL = $(rep.magnitude[mp][2]),\n"
        end
        if haskey(rep.tilt, mp)
            mpString *= "\tT$mp = $(rep.tilt[mp]),\n"
        end
    end
    return mpString
end



function make_ele_str(ele::pj.YAMLNode)
    props = ele[1]
    eleString = pj.node_key(ele[1]) * ": "

    ele_kind = String(props["kind"])
    if ele_kind == "Lattice"
        return ""
    else
        println("Translating ele $(pj.node_key(props))")

        ele_kind_bmad, args = bmad_kind(ele_kind)

        eleString *= ele_kind_bmad
        if isnothing(args)
            eleString *= ",\n"
        end
    end

    for key in keys(props)
        if key == "length"
            eleString *= "\t" * "L = $(String(props["length"]))," * "\n"
        elseif key == "ACKickerP"
            error("ACKickerP not yet supported")
        elseif key == "ApertureP"
            apertureP = props["ApertureP"]
            
            tmp = ""
            has_xmin   = haskey(apertureP, "x_min");    has_xmax  = haskey(apertureP, "x_max")
            has_xwidth = haskey(apertureP, "x_width");  has_xcen  = haskey(apertureP, "x_center")
            if (has_xmin || has_xmax) && (has_xwidth || has_xcen)
                println("
                Ignoring ApertureP of element $(pj.node_key(ele[1])). 
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
            if !isempty(tmp)
                eleString *= "\t" * tmp * "\n"
            end

            tmp = ""
            has_ymin   = haskey(apertureP, "y_min");    has_ymax  = haskey(apertureP, "y_max")
            has_ywidth = haskey(apertureP, "y_width");  has_ycen  = haskey(apertureP, "y_center")
            if (has_ymin || has_ymax) && (has_ywidth || has_ycen)
                println("
                Ignoring ApertureP of element $(pj.node_key(ele[1])). 
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
            if !isempty(tmp)
                eleString *= "\t" * tmp * "\n"
            end

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
                if !isempty(tmp)
                    eleString *= "\t" * tmp * "\n"
                end
            end
        elseif key == "BeamBeamP"
            bbP = props["BeamBeamP"]
            #=for bbkey in keys(bbP)
                if bbkey == "sigma_x"
                    eleString *= "$bbkey = $(String(bbP[bbkey])),"
                elseif bbkey == "sigma_y"
                    eleString *= "$bbkey = $(String(bbP[bbkey])),"
                elseif bbkey == "sigma_z"
                    eleString *= "$bbkey = $(String(bbP[bbkey])),"
                elseif bbkey == "alpha_x"
                    eleString *= "$bbkey = $(String(bbP[bbkey])),"
                elseif bbkey == "beta_x"
                    eleString *= "$bbkey = $(String(bbP[bbkey])),"
                elseif bbkey == "alpha_y"
                    eleString *= "$bbkey = $(String(bbP[bbkey])),"
                elseif bbkey == "beta_y"
                    eleString *= "$bbkey = $(String(bbP[bbkey])),"
                elseif bbkey == "charge"
                    eleString *= "$bbkey = $(String(bbP[bbkey])),"
                elseif bbkey == "energy"
                    eleString *= "$bbkey = $(String(bbP[bbkey])),"
                elseif bbkey == "N_particle"
                    eleString *= "$bbkey = $(String(bbP[bbkey])),"
                end
            end=#
            error("$(pj.node_key(props)): BeamBeamP not translated yet")            
        elseif key == "BendP"
            bendP = props["BendP"]
            has_e1 = haskey(bendP, "e1");  has_e1_rect  = haskey(bendP, "e1_rect");
            has_e2 = haskey(bendP, "e2");  has_e2_rect  = haskey(bendP, "e2_rect");
            if (has_e1 || has_e2) && (has_e1_rect || has_e2_rect)
                error("$(pj.node_key(props)): should not have both e1 and e1_rect, nor both e2 and e2_rect")
            end

            _keys = keys(bendP)
            isempty(_keys) && continue
            for bkey in _keys
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
                    error("$(pj.node_key(props)): L_chord is a derived quantity for SBend elements")
                elseif bkey == "L_sagitta"
                    error("$(pj.node_key(props)): L_sagitta is a derived quantity for SBend/RBend elements")
                elseif bkey == "tilt_ref"
                    tmp *= "ref_tilt = $(String(bendP["tilt_ref"])),"
                end

                if !isempty(tmp)
                    eleString *= "\t" * tmp * "\n"
                end
                
            end
        elseif key == "BodyShiftP"
            bodyshiftP = props["BodyShiftP"]
            _keys = keys(bodyshiftP)
            isempty(_keys) && continue
            for bskey in _keys
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
                if !isempty(tmp)
                    eleString *= "\t" * tmp * "\n"
                end
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

            fill_multipoles!(full, mmP, pj.node_key(ele[1]))

            if all(values(full.normalized))
                # eleString *= "\tfield_master = F,\n" # (Default)
            elseif all(!, values(full.normalized)) && ele_kind != "RFCavity"
                eleString *= "\tfield_master = T,\n"
            else
                error("$(pj.node_key(props)): Multipoles of one element must be all normalized or all unnormalized.")
            end

            rep = KindMap(ele_kind)(full)   # pick the element-specific representation, then down-convert
            eleString *= mp_key(rep)

        elseif key == "MetaP"
            # metaP = props["MetaP"]
            # for mkey in keys(metaP)
            #     if mkey == "alias"
            #         eleString *= "alias = $(String(metaP["alias"])),"
            #     elseif mkey == "label"
            #         eleString *= "label = $(String(metaP["label"])),"
            #     elseif mkey == "description"
            #         eleString *= "description = $(String(metaP["description"])),"
            #     end
            # end
            println("MetaP not supported in Bmad")
        elseif key == "PatchP"
            patchP = props["PatchP"]
            _keys = keys(patchP)
            isempty(_keys) && continue
            for pkey in _keys
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
                if !isempty(tmp)
                    eleString *= "\t" * tmp * "\n"
                end
            end
        elseif key == "RFP"
            rfP = props["RFP"]
            if String(props["kind"]) == "CrabCavity"
                error("$(pj.node_key(props)): CrabCavity not yet translated")
            end
            _keys = keys(rfP)
            isempty(_keys) && continue
            for rfkey in _keys
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
                        println("$(pj.node_key(props)): gradient not yet supported, replacing with voltage = gradient * length")
                    else
                        error("$(pj.node_key(props)): `gradient` not yet supported & `length` is undefined => voltage is undefined")
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
                        error("$(pj.node_key(props)): `Accelerating` phase is not supported with phi0_autoscale in Bmad")
                    elseif zp == "BELOW_TRANSITION"
                        tmp *= "rf_phase_below_transition_ref = T,"
                    elseif zp == "ABOVE_TRANSITION"
                        tmp *= "rf_phase_below_transition_ref = F,"
                    else
                        println("$(pj.node_key(props)): unknown zero_phase type")
                    end

                elseif rfkey == "L_active"
                    error("$(pj.node_key(props)): `L_active` is a dependent parameter in Bmad")

                elseif rfkey == "dE_ref"
                    error("$(pj.node_key(props)): needs translation to LCavity for `dE_ref`")
                end
                if !isempty(tmp)
                    eleString *= "\t" * tmp * "\n"
                end
            end
            if haskey(rfP, "frequency") && haskey(rfP, "harmon")
                error("$(pj.node_key(props)): can only define `frequency` or `harmon` but not both")
            end
        elseif key == "SolenoidP"
            solP = props["SolenoidP"]
            if !isempty(keys(solP))
                if haskey(solP, "Ksol")
                    eleString *= "$Ks = $(String(solP[Ksol])),"
                elseif haskey(solP, "Bsol")
                    eleString *= "$Bs_field = $(String(solP[Bsol])),"
                else
                    println("$(pj.node_key(props)) - unknown key(s): $keys(solP)")
                end
            end
        elseif key == "TrackingP"
            trackingP = props["TrackingP"]
            _keys = keys(trackingP)
            isempty(_keys) && continue
            for tkey in _keys
                if tkey == "Bmad"
                end
            end
        elseif key == "ReferenceChangeP"
            if ele_kind_bmad != "Patch"
                error("$(pj.node_key(props)): Bmad reference changes only allowed in Patch elements (PALS: Patch / RefereneChange)")
                continue
            else
                refchangeP = props["ReferenceChangeP"]
                _keys = keys(refchangeP)
                isempty(_keys) && continue
                for rkey in _keys
                    if rkey == "dtime_ref"
                        eleString *= "t_offset = $(String(refchangeP["dtime_ref"])),"

                    elseif rkey == "dE_ref"
                        eleString *= "E_tot_offset = $(String(refchangeP["dE_ref"])),"

                    elseif rkey == "dpc_ref"
                        error("$(pj.node_key(props)): dpc_ref (p0c_offset) not supported by Bmad, only E_tot_offset")

                    elseif rkey == "time_ref"
                        error("$(pj.node_key(props)): setting time_ref is not supported by Bmad")

                    elseif rkey == "E_tot_ref"
                        eleString *= "E_tot_set = $(String(refchangeP["E_tot_ref"])),"

                    elseif rkey == "pc_ref"
                        eleString *= "p0c_set = $(String(refchangeP["pc_ref"])),"

                    elseif rkey == "species_ref"
                        error("$(pj.node_key(props)): changing species in-beamline is not supported by Bmad")
                    end
                end
            end
        end
    end

    idx = findlast(==(','), eleString)
    if !isnothing(idx)
        eleString = eleString[1:idx-1] * eleString[idx+1:end]
    end
    return eleString
end

function main(file_dir::String)
    in_path  = file_dir
    out_path = first(splitext(in_path)) * "_out.bmad"
    file     = pj.parse_file(in_path)
    facility = file["PALS"]["facility"]
    open(out_path, "w") do io
        ref_str     = ""
        particle_str= ""
        ele_str     = ""
        full_bl_str = ""
        lattice_str = ""
        lattice_msc = ""
        beamlines   = []
        N_lattices  = 0
        for ele in facility
            props = ele[1]
            if haskey(props, "kind")
                pals_kind = String(props["kind"])
                if pals_kind == "BeginningEle"
                    ref_str, particle_str = make_init_str(ele)
                elseif pals_kind == "BeamLine"
                    bl_name = pj.node_key(ele[1])
                    bl_str = make_bl_str(ele)
                    push!(beamlines, bl_str)
                    bl_str = ((length(bl_str) < 80) ? bl_str : ("\n\t" * bl_str * "\n\t"))
                    full_bl_str *= "$bl_name: line = ($(bl_str))"
                    full_bl_str *= "\n\n"
                elseif pals_kind == "Lattice"
                    N_lattices += 1
                    N_lattices > 1 && error("\n
                    Different BeamLine complexes must be translated from separate files.\n
                    Bmad only supports one branching lattice per file.\n
                    Consider using different Tao universes.\n")
                    lattices = props["branches"]
                    isempty(lattices) && continue
                    N_bl = length(lattices)
                    if N_bl == 1
                        bl = first(lattices)
                        if pj.is_scalar(bl)
                            lattice_str *= "$(String(bl))"
                            periodic = "open"
                        elseif pj.is_map(bl)
                            bl_props = bl[1]
                            lattice_str *= "$(pj.node_key(bl_props)), "

                            if !isempty(keys(bl_props))
                                if haskey(bl_props, "periodic")
                                    if bl_props["periodic"] == "true"
                                        periodic = "closed"
                                    else
                                        periodic = "open"
                                    end
                                else
                                    periodic = "open"
                                end
                            else
                                periodic = "open"
                            end
                        elseif pj.is_sequence(bl)
                            error("Expanding lattices is not done during PALS>Bmad translation")
                        else
                            error("This object is neither a scalar, map, nor sequence: ", bl)
                        end
                        lattice_msc *= "parameter[geometry] = $periodic"
                        write(io, "!======================================================================" * "\n")
                        write(io, lattice_msc * "\n\n")
                        lattice_msc = ""
                    else
                        for bl in lattices
                            if pj.is_scalar(bl)
                                lattice_str *= "$(String(bl)), "
                                periodic = "open"
                            elseif pj.is_map(bl)
                                bl_props = bl[1]
                                lattice_str *= "$(pj.node_key(bl_props)), "

                                if !isempty(keys(bl_props))
                                    if haskey(bl_props, "periodic")
                                        if bl_props["periodic"] == "true"
                                            periodic = "closed"
                                        else
                                            periodic = "open"
                                        end
                                    else
                                        periodic = "open"
                                    end
                                else
                                    periodic = "open"
                                end
                            elseif pj.is_sequence(bl)
                                error("Expanding lattices is not done during PALS>Bmad translation")
                            else
                                error("This object is neither a scalar, map, nor sequence: ", bl)
                            end
                            lattice_msc *= "$(pj.node_key(bl_props))[geometry] = $periodic" * "\n"
                        end
                    end
                    idx = findlast(==(','), lattice_str)
                    if !isnothing(idx) 
                        lattice_str = lattice_str[1:idx-1] * lattice_str[idx+1:end]
                    end
                else
                    ele_str *= make_ele_str(ele) * "\n"
                end
            end
        end

        !isempty(ref_str) && write(io, ref_str * "\n")
        !isempty(particle_str) && write(io, particle_str * "\n\n")
        write(io, "!======================================================================" * "\n")
        write(io, "! Element definitions " * "\n\n")
        !isempty(ele_str) && write(io, ele_str)
        write(io, "!======================================================================" * "\n")
        write(io, "! Beamline definitions " * "\n\n")
        !isempty(full_bl_str) && write(io, full_bl_str)
        !isempty(lattice_msc) && write(io, lattice_msc)
        write(io, "!======================================================================" * "\n")
        write(io, "! Branch structure " * "\n\n")
        !isempty(lattice_str) && write(io, "use, " * lattice_str)
    end
end


if abspath(PROGRAM_FILE) == @__FILE__
    if isempty(ARGS)
        error("Usage: julia toBmad.jl <input.pals.yaml>")
    end
    main(ARGS[1])
end