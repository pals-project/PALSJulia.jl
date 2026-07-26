# Translating to SciBmad and Bmad

PALSJulia can translate a PALS-format lattice into the two Cornell accelerator
formats:

- **`src/toSciBmad.jl`** — emits a [SciBmad](https://github.com/bmad-sim/SciBmad.jl)
  / [Beamlines](https://github.com/bmad-sim/Beamlines.jl) description.
- **`src/toBmad.jl`** — emits a classic [Bmad](https://www.classe.cornell.edu/bmad/)
  lattice.

Both translators take a lattice already parsed by `parse_file`,
walk the element list, and map each PALS element and its parameters
onto the corresponding target-format element.

## Running the translators

Translating is a three-step process: parse, translate, write. `parse_file` reads a
PALS-YAML file into a parsed tree (a `YAMLNode`); `pals_to_bmad` / `pals_to_scibmad`
translate that tree into an in-memory model of the *target* lattice (a `BmadLattice` /
`SciBmadLattice` of elements, beamlines, and parameters); and `write_bmad_file` /
`write_scibmad_file` take that structure and an output path and serialize the lattice file:

```julia
using PALSJulia
using PALSJulia: parse_file

bmad = pals_to_bmad(parse_file(joinpath("lattice_files", "bta.pals.yaml")))
write_bmad_file(bmad, joinpath("lattice_files", "bta.pals_out.bmad"))

scibmad = pals_to_scibmad(parse_file(joinpath("lattice_files", "convert.pals.yaml")))
write_scibmad_file(scibmad, joinpath("lattice_files", "convert.pals_out.jl"))
```

The [`examples/`](https://github.com/pals-project/PALSJulia/tree/main/examples)
directory has runnable scripts, such as `examples/pals_to_bmad.jl`.

## Element and parameter mapping

PALS element kinds and their parameters do not map one-to-one onto Bmad. The
translators encode the conversions — renamed parameters, unit changes, and
cases that have no equivalent (and are skipped with a warning). For example,
an `ApertureP` becomes a Bmad `ApertureParams`, with `x_min`/`x_max` mapped to
`x1_limit`/`x2_limit` (or derived from `x_center`/`x_width`).

The complete, element-by-element list of these mappings is given in the
[Parameter mapping reference](#parameter-mapping-reference) below. Consult it
when adding support for a new element or when a parameter comes through
untranslated.

## Extending a translator

To add support for a new element or parameter:

1. Find its PALS definition and decide on the target-format equivalent; record
   it in the [Parameter mapping reference](#parameter-mapping-reference) below.
2. Add the mapping to the element builder — `_make_bmad_ele` in
   `src/toBmad.jl` or `_make_scibmad_ele` in `src/toSciBmad.jl` — and to any
   helper it calls (e.g. `_ele_to_bmad_str`, `_make_bmad_line`, or
   `_ele_to_scibmad_str`, `_make_scibmad_beamline`).
3. Translate a lattice that exercises the element and check the output.

## Parameter mapping reference

The following is the element-by-element mapping between PALS parameter groups
and their SciBmad/Bmad equivalents.

### ACKickerP --> None

### ApertureP --> ApertureParams
- x_min --> x1_limit
- x_max --> x2_limit
- x_width and x_center:
    - x1_limit = x_center - x_width / 2
    - x2_limit = x_center + x_width / 2
- Note: Either both min and max are defined, or width and center are defined, not both.
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

### BeamBeamP --> Not in SciBmad yet

### BendP --> BendParams
- radius_ref -> caluclated (Bmad: rho)
- Bn0_ref -> calculated (Bmad: B_field)
- e1 --> e1
- e2 --> e2
- e1_rect --> calculated
- e2_rect --> calcualted
- edge1_int --> edge1_int
- edge2_int --> edge2_int
- g_ref --> g_ref
- h1 --> not in scibmad
- h2 --> not in scibmad
- L_chord --> calculated
- L_sagitta --> calculated
- tilt_ref --> tilt_ref

### BodyShiftP --> AlignmentParams
- x_offset --> x_offset
- y_offset --> y_offset
- z_offset --> z_offset
- x_rot --> x_rot
- y_rot --> y_rot
- z_rot --> tilt

### ElectricMultipoleP --> Not in SciBmad yet

### FloorP --> Calculated

### FloorShiftP --> Set in floor shift element (to be added to scibmad)

### ForkP --> Needs to be Implemented in scibmad

### GirderP In Contruction

### MagneticMultipoleP --> BMultipoleParams
- tiltN --> tiltN
- [BK][ns]NL? --> [BK][ns]NL?
- BnN(L) --> BnN(L)
- Note (Bmad): the normal component of the multipole that is an element's own strength becomes
  that strength: `Kn1` --> `K1` for a quadrupole, `Kn2` --> `K2`, `Kn3` --> `K3`, and `Kn0` -->
  `dg` for a bend (`Bn1` --> `B1_GRADIENT`, ..., `Bn0` --> `db_field`). Every other order stays
  a multipole, and becomes the integrated `An`/`Bn`.
- Note (Bmad): PALS states a bend's field outright, where Bmad states its departure from the
  reference bend. So `Kn0` is translated as `dg = Kn0 - g_ref` -- against `1/radius_ref` when
  the reference bend is given as a radius, and against `Bn0_ref` when the field is not
  normalized. A field equal to the reference bend departs from it by nothing, and no `dg` is
  written. The two flavors cannot be mixed: measuring a `Kn0` against a `Bn0_ref` (or the
  reverse) takes the reference momentum, which belongs to the branch and not to the element.

### MetaP --> MetaParams
- alias --> alias (Bmad: alias)
- label --> label (Bmad: type)
- description --> description (Bmad: descrip)
- ID --> none
- location --> none
- history --> none
- Note: any other (non-standard) component --> none
- Note: a component holding a structure rather than a string is not translated.

### ParticleP --> Create new bunch

### PatchP --> PatchParams
- x_offset --> x_offset
- y_offset --> y_offset
- z_offset --> z_offset
- t_offset --> dt (not in PALS yet)
- x_rot --> x_rot
- y_rot --> y_rot
- z_rot --> z_rot
- flexible --> none
- ref_coords --> none
- user_sets_length --> none

### ReferenceP --> Beamline Properties
- species_ref --> species_ref
- pc_ref --> pc_ref
- E_tot_ref --> E_ref
- time_ref --> none
- location --> none

### ReferenceChangeP --> Beamline Properties
- extra_dtime_ref --> none
- dE_ref --> dE_ref
- E_tot_ref --> E_ref
- species_ref --> species_ref

### RFP --> RFParams
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
- num_cells --> tracking_method = SaganCavity(num_cells)
- zero_phase --> zero_phase
    - ACCELERATING --> Accelerating
    - BELOW_TRANSITION --> BelowTransition
    - ABOVE_TRANSITION --> AboveTransition

### SolenoidP --> BMultipoleParams
- Ksol --> Ksol
- Bsol --> Bsol

### TrackingP --> UniversalParams.tracking_method

### Lattices
- Beamlines --> Beamlines
- To be added: Lattices in PALS --> Lattices

### Constants and variables --> Bmad `name = value` definitions
- `constants:` / `variables:` list entry --> `name = value`
- `kind: constant` / `kind: variable` definition --> `name = value`
- Note: Bmad draws no constant/variable distinction, so both translate the same way.
- Note: definitions directly under the `PALS` node are translated as well as the facility's own.
- Note: a definition with no `value` takes the PALS default of zero.
- Note: the definitions are written, in the order the PALS file gives them, ahead of every
  other section of the Bmad file. Bmad, unlike PALS, resolves a name against what the file
  has defined *above* the point of use.
- Not translated to SciBmad.

### TODO
- translating expression
- names of fundamental constants
- names of functions (tan)
- sinc --> sincu
