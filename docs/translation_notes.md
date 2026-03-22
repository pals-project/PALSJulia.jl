# Translation Notes

## ACKickerP (Not in SciBmad)?

## ApertureP --> ApertureParams
- x_min --> x1_limit
- x_max --> x2_limit
- x_width and x_center:
    - x1_limit = x_center - x_width / 2
    - x2_limit = x_center + x_width / 2

- y_min --> y1_limit
- y_may --> y2_limit
- y_width and y_center:
    - y1_limit = y_center - y_width / 2
    - y2_limit = y_center + y_width / 2

- shape --> aperture_shape
    - RECTANGULAR --> Rectangular
    - ELLIPTICAL --> Elliptical
    - VERTICES --> none
    - CUSTOM_SHAPE --> none

- location --> aperture_at
    - ENTRANCE_END --> Entrance
    - EXIT_END --> Exit
    - BOTH_ENDS --> BothEnds
    - EVERYWHERE --> BothEnds
    - CENTER --> BothEnds
    - NOWHERE --> none

- aperture_shifts_with_body --> aperture_shifts_with_body
- aperture_active --> aperture_active
- vertices --> none
- material --> none
- thickness --> none

## BeamBeamP --> Not in SciBmad yet

## BendP --> BendParams
- rho_ref -> none
- bend_field_ref -> none
- e1 --> e1
- e2 --> e2
- e1_rect --> calculated?
- e2_rect --> calcualted?
- edge1_int --> edge1_int
- edge2_int --> edge2_int
- g_ref --> g_ref
- h1 --> calculated?
- h2 --> calculated?
- L_chord --> calculated?
- L_sagitta --> calculated?
- tilt_ref --> tilt_ref

## BodyShiftP --> AlignmentParams
- x_offset --> x_offset
- y_offset --> y_offset
- z_offset --> z_offset
- x_rot --> x_rot
- y_rot --> y_rot
- z_rot --> tilt

## ElectricMultipoleP --> Not in SciBmad yet

## FloorP --> Calculated?

## FloorShiftP --> Calculated?

## ForkP --> Needs to be Implemented

## GirderP In Contruction

## MagneticMultipoleP --> BMultipoleParams
- tiltN --> tiltN
- [BK][ns]NL? --> [BK][ns]NL?
- BnN(L) --> BnN(L)

## MetaP --> Working on it 
- see misc.jl

## PatchP --> PatchParams
- x_offset --> x_offset
- y_offset --> y_offset
- z_offset --> z_offset
- x_rot --> x_rot
- y_rot --> y_rot
- z_rot --> z_rot
- flexible --> none
- ref_coords --> ??
- user_sets_length --> none

## RFP --> RFParams
- frequency --> rate, rate_meaning = false
- harmon --> rate, if rate_meaning = true
- if neither frequency or harmon exist, set rate_meaning = -1
- voltage --> voltage
- gradient --> none
- phase --> phi0
- multipass_phase --> none
- cavity_type --> traveling_wave
    - STANDING_WAVE --> false
    - TRAVELING_WAVE --> true
- n_cell --> none
- zero_phase --> zero_phase
    - ACCELERATING --> Accelerating
    - BELOW_TRANSITION --> BelowTransition
    - ABOVE_TRANSITION --> AboveTransition

## SolenoidP --> BMultipoleParams
- Ksol --> Ksol
- Bsol --> Bsol

## TrackingP --> UniversalParams.tracking_method?

## TODO
- ReferenceP
- ReferenceChangeP
- InitialParticleP

## Questions/Comments
- What is angle_ref in BendP, what are the one's that need translation and what are independent
- BendP: error in docs for g_ref, rho_ref
- SciBmad MapParams?
- SciBmad FourPotentialParams
- PatchP: Scibmad has dt
- RFP: Scibmad has is_crabcavity (is this just rf cavity with length = 0?)
