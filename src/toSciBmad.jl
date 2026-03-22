# read in lattice, get elements and put in dictionary, put in lattice
import Pkg
Pkg.activate(joinpath(@__DIR__, ".."))
import pals_julia as pj
using Beamlines

# submit issue to pals: inconsistency with upper/lower pals
# ele should be an element
# don't write default values?
function make_ele_str(ele::pj.YAMLNode)
    key_list = keys(ele)
    props = ele[key_list[1]] 
    paramString = ""

    # are the reference params given in beginningele?
    if pj.haskey(props, "kind") && String(props["kind"]) == "BeamLine"
        paramString *= "$(key_list[1]) = Beamline("
        if !pj.haskey(props, "line"); return; end;
        line = props["line"]
        paramString *= "["
        for i in 1:length(line)
            paramString *= string(String(line[i]), ",")
        end
        paramString *= "]"
        paramString *= ")"
        return paramString
    end
    paramString *= "$(key_list[1]) = LineElement("
    if pj.haskey(props, "kind"); paramString *= "kind = $(String(props["kind"])),"; end
    if pj.haskey(props, "length"); paramString *= "L = $(String(props["length"])),"; end
    if pj.haskey(props, "ACKickerP")
        println("ACKickerP not yet supported")
    end
    if pj.haskey(props, "ApertureP")
        apertureP = props["ApertureP"]
        if pj.haskey(apertureP, "x_min"); paramString *= "x1_limit = $(String(apertureP["x_min"])),"; end
        if pj.haskey(apertureP, "x_max"); paramString *= "x2_limit = $(String(apertureP["x_max"])),"; end
        if pj.haskey(apertureP, "x_width") && pj.haskey(apertureP, "x_center")
            width = Int(apertureP["x_width"])
            center = Int(apertureP["x_center"])
            paramString *= "x1_limit = $(center - width / 2),"
            paramString *= "x2_limit = $(center + width / 2),"
        end
        if pj.haskey(apertureP, "y_min"); paramString *= "y1_limit = $(String(apertureP["y_min"])),"; end
        if pj.haskey(apertureP, "y_max"); paramString *= "y2_limit = $(String(apertureP["y_max"])),"; end
        if pj.haskey(apertureP, "y_width") && pj.haskey(apertureP, "y_center")
            width = Int(apertureP["y_width"])
            center = Int(apertureP["y_center"])
            paramString *= "x1_limit = $(center - width / 2),"
            paramString *= "x2_limit = $(center + width / 2),"
        end
        if pj.haskey(apertureP, "shape")
            shape = String(apertureP["shape"])
            if shape == "ELLIPTICAL"
                paramString *= string("aperture_shape = ", "ApertureShape.Elliptical,")
            elseif shape == "RECTANGULAR"
                paramString *= string("aperture_shape = ", "ApertureShape.Rectangular,")
            else
                println("shape $shape is not supported")
            end
        end
        #if everywhere or center translate to both ends and print message
        if pj.haskey(apertureP, "location")
            location = String(apertureP["location"])
            if location == "ENTRANCE_END"
                paramString *= string("aperture_at = ", "ApertureAt.Entrance,")
            elseif location == "EXIT_END"
                paramString *= string("aperture_at = ", "ApertureAt.Exit,")
            elseif location == "BOTH_ENDS"
                paramString *= string("aperture_at = ", "ApertureAt.BothEnds,")
            elseif location == "EVERYWHERE" || location == "CENTER"
                paramString *= string("aperture_at = ", "ApertureAt.BothEnds,")
                println("location $location not supported, set to BothEnds")
            elseif location == "NOWHERE"
                println("location $location not supported")
            end
        end
        if pj.haskey(apertureP, "aperture_shifts_with_body")
            shifts = lowercase(String(apertureP["aperture_shifts_with_body"]))
            if shifts == "false"
                paramString *= string("aperture_shifts_with_body = ", "false,")
            elseif shifts == "true"
                paramString *= string("aperture_shifts_with_body = ", "true,")
            end
        end
        if pj.haskey(apertureP, "aperture_active")
            active = lowercase(String(apertureP["aperture_active"]))
            if active == "true"
                paramString *= string("aperture_active = ", "true,")
            elseif active == "false"
                paramString *= string("aperture_active = ", "false,")
            end
        end
        if pj.haskey(apertureP, "vertices"); println("vertices not yet supported"); end
        if pj.haskey(apertureP, "material"); println("material not yet supported"); end
        if pj.haskey(apertureP, "thickness"); println("thickness not yet supported"); end
    end
    if pj.haskey(props, "BeamBeamP")
        println("BeamBeamP not yet supported")
    end
    if pj.haskey(props, "BendP")
        bendP = props["BendP"]
        if pj.haskey(bendP, "rho_ref"); println("rho_ref not yet supported"); end
        if pj.haskey(bendP, "bend_field_ref"); println("bend_field_ref not yet supported"); end
        if pj.haskey(bendP, "e1"); paramString *= "e1 = $(String(bendP["e1"])),"; end
        if pj.haskey(bendP, "e2"); paramString *= "e2 = $(String(bendP["e2"])),"; end
        if pj.haskey(bendP, "e1_rect"); println("e1_rect not yet supported"); end
        if pj.haskey(bendP, "e2_rect"); println("e2_rect not yet supported"); end
        if pj.haskey(bendP, "edge1_int"); paramString *= "edge1_int = $(String(bendP["edge1_int"])),"; end
        if pj.haskey(bendP, "edge2_int"); paramString *= "edge2_int = $(String(bendP["edge2_int"])),"; end
        if pj.haskey(bendP, "g_ref"); paramString *= "g_ref = $(String(bendP["rho_ref"])),"; end
        if pj.haskey(bendP, "h1"); println("h1 not yet supported"); end
        if pj.haskey(bendP, "h2"); println("h2 not yet supported"); end
        if pj.haskey(bendP, "L_chord"); println("L_chord not yet supported"); end
        if pj.haskey(bendP, "L_sagitta"); println("L_sagitta not yet supported"); end
        if pj.haskey(bendP, "tilt_ref"); paramString *= "tilt_ref = $(String(bendP["tilt_ref"])),"; end

    end
    if pj.haskey(props, "BodyShiftP")
        bodyshiftP = props["BodyShiftP"]
        if haskey(bodyshiftP, "x_offset"); paramString *= "x_offset = $(String(bodyshiftP["x_offset"])),"; end
        if haskey(bodyshiftP, "y_offset"); paramString *= "y_offset = $(String(bodyshiftP["y_offset"])),"; end
        if haskey(bodyshiftP, "z_offset"); paramString *= "z_offset = $(String(bodyshiftP["z_offset"])),"; end
        if haskey(bodyshiftP, "x_rot"); paramString *= "x_rot = $(String(bodyshiftP["x_rot"])),"; end
        if haskey(bodyshiftP, "y_rot"); paramString *= "y_rot = $(String(bodyshiftP["y_rot"])),"; end
        if haskey(bodyshiftP, "z_rot"); paramString *= "tilt = $(String(bodyshiftP["z_rot"])),"; end
    end
    if pj.haskey(props, "ElectricMultipoleP")
        println("ElectricMultipoleP not yet supported")
    end
    if pj.haskey(props, "FloorP")
        println("FloorP not yet supported")
    end
    if pj.haskey(props, "FloorShiftP")
        println("FloorShiftP not yet supported")
    end
    if pj.haskey(props, "ForkP")
        println("ForkP not yet supported")
    end
    if pj.haskey(props, "GirderP")
        println("GirderP not yet supported")
    end
    # who should check that each pole is only normalized or integrated
    # if an order has one parameter, is it guaranteed to have the others, or set to default
    if pj.haskey(props, "MagneticMultipoleP")
        mmP = props["MagneticMultipoleP"]
        for key in keys(mmP) 
            paramString *= "$(String(key)) = $(String(mmP[key])),"
        end
    end
    if pj.haskey(props, "MetaP")
        println("MetaP not yet supported")
    end
    if pj.haskey(props, "PatchP")
        patchP = props["PatchP"]
        if pj.haskey(patchP, "x_offset"); paramString *= "dx = $(String(patchP["x_offset"])),"; end
        if pj.haskey(patchP, "y_offset"); paramString *= "dy = $(String(patchP["y_offset"])),"; end
        if pj.haskey(patchP, "z_offset"); paramString *= "dz = $(String(patchP["z_offset"])),"; end
        if pj.haskey(patchP, "x_rot"); paramString *= "dx = $(String(patchP["x_rot"])),"; end
        if pj.haskey(patchP, "y_rot"); paramString *= "dy = $(String(patchP["y_rot"])),"; end
        if pj.haskey(patchP, "z_rot"); paramString *= "dz = $(String(patchP["z_rot"])),"; end
        if pj.haskey(patchP, "flexible"); println("flexible not yet supported"); end
        if pj.haskey(patchP, "ref_coords"); println("ref_coords not yet supported"); end
        if pj.haskey(patchP, "user_sets_length"); println("user_sets_length not yet supported"); end
    end
    if pj.haskey(props, "RFP")
        rfP = props["RFP"]
        if pj.haskey(rfP, "frequency")
            paramString *= "rate = $(String(rfP["frequency"])),"
            paramString *= "rate_meaning = false,"
        elseif pj.haskey(rfP, "harmon")
            paramString *= "rate = $(String(rfP["harmon"])),"
            paramString *= "rate_meaning = true,"
        else 
            paramString *= "rate_meaning = -1,"
        end
        if pj.haskey(rfP, "voltage"); paramString *= "voltage = $(String(rfP["voltage"])),"; end
        if pj.haskey(rfP, "gradient"); println("gradient not yet supported"); end
        if pj.haskey(rfP, "phase"); paramString *= "phi0 = $(String(rfP["phase"])),"; end
        if pj.haskey(rfP, "multipass_phase"); println("multipass_phase not yet supported"); end
        if pj.haskey(rfP, "cavity_type"); paramString *= "traveling_wave = $(String(rfP["cavity_type"]) == "TRAVELING_WAVE"),"; end
        if pj.haskey(rfP, "n_cell"); println("n_cell not yet supported"); end
        if pj.haskey(rfP, "zero_phase")
            zp = String(rfP["zero_phase"])
            if zp == "ACCELERATING"
                paramString *= "zero_phase = Accelerating"
            elseif zp == "BELOW_TRANSITION"
                paramString *= "zero_phase = BelowTransition"
            elseif zp == "ABOVE_TRANSITION"
                paramString *= "zero_phase = AboveTransition"
            end
        end
    end
    # only add if Scibmad?
    if pj.haskey(props, "SolenoidP")
        solP = props["SolenoidP"]
        for key in keys(solP) 
            paramString *= "$(String(key)) = $(String(solP[key])),"
        end
    end
    if pj.haskey(props, "TrackingP")
        trackingP = props["TrackingP"]
        if pj.haskey(trackingP, "SciBmad")
            sbm = trackingP["SciBmad"]
            if pj.haskey(sbm, "tracking_method")
                if String(sbm["tracking_method"]) == "scibmad_standard"
                    paramString *= "tracking_method = SciBmadStandard()"
                end
            end
        end
    end
    paramString *= ")"
    return paramString
end

#function to create string 
#function to take string output to file or eval

function main()
    # lats = pj.get_lattices("../lattice_files/convert.pals.yaml", "lat1")
    lat = pj.parse_file("../lattice_files/convert.pals.yaml")
    open("../lattice_files/convert_out.jl", "w") do io
        for i in 1:length(lat)
            ele = lat[i]
            write(io, make_ele_str(ele) * "\n")
        end
    end
end

main()