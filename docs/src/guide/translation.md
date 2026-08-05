# Translating to SciBmad, Bmad and MAD-X

PALSParserJ can translate a PALS-format lattice into three accelerator formats:

- **`src/toSciBmad.jl`** — emits a [SciBmad](https://github.com/bmad-sim/SciBmad.jl)
  / [Beamlines](https://github.com/bmad-sim/Beamlines.jl) description.
- **`src/toBmad.jl`** — emits a classic [Bmad](https://www.classe.cornell.edu/bmad/)
  lattice.
- **`src/toMadx.jl`** — emits a [MAD-X](https://mad.web.cern.ch/mad/) lattice.

All three translators take a lattice already parsed by `parse_file`,
walk the element list, and map each PALS element and its parameters
onto the corresponding target-format element.

## Running the translators

Translating is a three-step process: parse, translate, write. `parse_file` reads a
PALS-YAML file into a parsed tree (a `YAMLNode`); `pals_to_bmad` / `pals_to_madx` /
`pals_to_scibmad` translate that tree into an in-memory model of the *target* lattice
(a `BmadLattice` / `MadxLattice` / `SciBmadLattice` of elements, beamlines, and
parameters); and `write_bmad_file` / `write_madx_file` / `write_scibmad_file` take that
structure and an output path and serialize the lattice file:

```julia
using PALSParserJ
using PALSParserJ: parse_file

bmad = pals_to_bmad(parse_file(joinpath("lattice_files", "bta.pals.yaml")))
write_bmad_file(bmad, joinpath("lattice_files", "bta.pals_out.bmad"))

madx = pals_to_madx(parse_file(joinpath("lattice_files", "bta.pals.yaml")))
write_madx_file(madx, joinpath("lattice_files", "bta.pals_out.madx"))

scibmad = pals_to_scibmad(parse_file(joinpath("lattice_files", "convert.pals.yaml")))
write_scibmad_file(scibmad, joinpath("lattice_files", "convert.pals_out.jl"))
```

The [`examples/`](https://github.com/pals-project/PALSParserJ.jl/tree/main/examples)
directory has runnable scripts, such as `examples/pals_to_bmad.jl` and
`examples/pals_to_madx.jl`.

## Element and parameter mapping

PALS element kinds and their parameters do not map one-to-one onto Bmad or MAD-X. The
translators encode the conversions — renamed parameters, unit changes, and
cases that have no equivalent (and are skipped with a warning). For example,
an `ApertureP` becomes a Bmad `ApertureParams`, with `x_min`/`x_max` mapped to
`x1_limit`/`x2_limit` (or derived from `x_center`/`x_width`).

The complete, element-by-element list of these mappings is given in the
[Parameter mapping reference](#parameter-mapping-reference) below. Consult it
when adding support for a new element or when a parameter comes through
untranslated. MAD-X differs from Bmad widely enough to be worth reading
[What MAD-X does differently](#what-mad-x-does-differently) first.

## Extending a translator

To add support for a new element or parameter:

1. Find its PALS definition and decide on the target-format equivalent; record
   it in the [Parameter mapping reference](#parameter-mapping-reference) below.
2. Add the mapping to the element builder — `_make_bmad_ele` in
   `src/toBmad.jl`, `_make_madx_ele` in `src/toMadx.jl`, or `_make_scibmad_ele` in
   `src/toSciBmad.jl` — and to any helper it calls (e.g. `_ele_to_bmad_str`,
   `_make_bmad_line`, `_ele_to_madx_str`, or `_ele_to_scibmad_str`,
   `_make_scibmad_beamline`).
3. Translate a lattice that exercises the element and check the output.

## What MAD-X does differently

Bmad and MAD-X share a great deal, but a PALS lattice meets the differences at
almost every element. The ones that shape the whole translation:

- **Every MAD-X strength is normalized.** MAD-X has no field-valued attribute at
  all, where Bmad has `field_master` and `B1_GRADIENT`. A PALS component stated as
  a field (`Bn1`, `Bsol`, `bend_field_ref`) is therefore divided by the signed
  rigidity `P0/q`, which the file defines once as
  `pals_brho := beam->brho * beam->charge / abs(beam->charge);` and leaves MAD-X to
  evaluate from its own `BEAM` command.
- **MAD-X coefficients carry no `1/n!`.** MAD-X states a multipole as
  `Kn L = (L/Brho) d^n By/dx^n`, and so does PALS, so a PALS `KnN` is MAD-X's `KN`
  outright. (Bmad's `An`/`Bn` do carry the factorial, which is why the Bmad
  translation divides by one and this one does not.)
- **MAD-X has a skew attribute for each of the orders an element owns** — `k1s`,
  `k2s`, `k3s` — so a tilted or skew multipole of the element's own order needs no
  multipole element of its own. But MAD-X magnets are strictly single-order:
  a quadrupole may not carry a sextupole component, and only a `multipole` element
  has the `knl`/`ksl` arrays. Any other order on a magnet is reported and dropped.
- **A bend's geometry and its field are the one `angle`.** MAD-X does not use `k0`
  in its bend map, so it has no equivalent of Bmad's `dg`, the departure of the
  field from the reference bend. PALS decouples the two (the actual field is `Kn0`,
  and `Kn0_from_g_ref` says whether it defaults to the reference field); MAD-X cannot.
  The reference geometry is what is written out; a `Kn0` that disagrees with it is
  reported and dropped, because writing the field out instead would move every element
  downstream of the bend.
- **A misalignment lives outside the element definition.** A PALS `BodyShiftP`
  becomes a `SELECT, FLAG=ERROR` / `EALIGN` pair after the `USE` statement, not an
  attribute of the element. MAD-X rotates about the entrance of an element where
  PALS and Bmad rotate about its centre, so the two agree only to first order in
  the angles.
- **MAD-X has no controller element.** A PALS `Controller` becomes what MAD-X has
  instead: its variables become ordinary MAD-X variables and each of its controls
  becomes a deferred assignment, `q1->k1 := 2*k;`. A `RELATIVE` controller has both
  the value it varies and its own starting point written into the assignment, MAD-X
  forbidding the circular `q1->k1 := q1->k1 + dk` and having no notion of a knob's
  delta. MAD-X variables are global where a PALS controller's are its own, so a name
  two controllers both claim is prefixed with the controller that owns it.
- **MAD-X units are not PALS units.** Energies are GeV against eV, voltages MV
  against V, frequencies MHz against Hz, and phases are counted in turns where PALS
  counts Twiss phases in radians. A value written as a number is converted during
  translation; one written as an expression is left for MAD-X to evaluate.
- **The longitudinal coordinate is measured against the energy.** MAD-X's `T`, `PT`
  and its dispersion are derivatives with respect to `pt = dE/(p0 c)` where PALS
  uses `pz = dp/p0`, and `pt = beta * pz`. Those quantities are written out divided
  or multiplied by MAD-X's own `beam->beta` rather than converted here.
- **Section order matters.** A MAD-X name has to be defined above the point of use,
  `BEAM` has to precede `USE`, and `EALIGN` can only follow it, there being no
  expanded sequence to apply an error to before then. `write_madx_file` writes the
  sections in that order.

## Parameter mapping reference

The following is the element-by-element mapping between PALS parameter groups
and their SciBmad/Bmad/MAD-X equivalents.

### Element kinds --> MAD-X keywords

- Bend --> sbend (PALS has the one bend, whose reference geometry is a sector)
- CrabCavity --> crabcavity
- Drift --> drift
- Kicker --> kicker
- Multipole --> multipole
- Octupole --> octupole
- Quadrupole --> quadrupole
- RFCavity --> rfcavity
- Sextupole --> sextupole
- Solenoid --> solenoid
- BeamBeam --> beambeam
- Mask --> collimator
- Instrument --> instrument
- Marker, BeginningEle --> marker
- Placeholder --> placeholder
- Patch --> changeref
- Taylor --> matrix (the map itself is not yet translated)
- ACKicker, Wiggler, Converter, EGun, Foil, Match, Fiducial, FloorShift, Fork,
  ReferenceChange, Girder, UnionEle, Feedback --> no MAD-X equivalent (an error)

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

- Note (MAD-X): MAD-X states a half extent about the axis and the offset of the
  centre separately, so both PALS forms come to `aperture = {x_half, y_half}` and
  `aper_offset = {x_center, y_center}`; `shape` becomes `apertype`
  (RECTANGULAR --> rectangle, ELLIPTICAL --> ellipse).
- Note (MAD-X): the `shape` decides which components describe the aperture. A
  `RECTANGULAR` or `ELLIPTICAL` one is bounded by its limits and ignores any vertices;
  a `VERTICES` (or `CUSTOM_SHAPE`) one is reported, MAD-X taking a vertex outline only
  from a file of its own, which PALS does not name.
- Note (MAD-X): MAD-X checks an aperture at the entrance of an element only, so
  `location` is not translated; nor are `aperture_shifts_with_body`, `material` and
  `thickness`, and an `aperture_active: false` cannot be expressed.
- Note (MAD-X): MAD-X cannot put an aperture on a drift — use a collimator — and
  its aperture values are positional, so a group that bounds one plane and not the
  other has the unbounded one written out as 1 m.

### BeamBeamP --> Not in SciBmad yet
- Note (MAD-X): sigma_x --> sigx, sigma_y --> sigy, charge --> charge,
  N_particle --> npart. MAD-X models the opposite beam as a four-dimensional lens,
  so sigma_z, alpha_x, beta_x, alpha_y, beta_y and energy have no equivalent.

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

- Note (MAD-X): PALS states a bend's geometry with any two of three sets of mutually
  dependent parameters — a curvature (`g_ref`, `radius_ref`, `Bn0_ref`), a length
  (`length`, `L_chord`, `L_rectangle`) and the angle (`angle_ref`) — one from each of
  two different sets. MAD-X wants one particular pair, the `angle` and the arc length
  `l`, so whichever pair was given is turned into that pair:
  `angle = g_ref * length`, `= 2*asin(g_ref*L_chord/2)`, `= asin(g_ref*L_rectangle)`;
  `l = angle_ref / g_ref`, `= angle_ref*L_chord/(2*sin(angle_ref/2))`,
  `= angle_ref*L_rectangle/sin(angle_ref)`. Only `Bn0_ref` needs `pals_brho`, the rest
  being pure geometry. A bend that states too little for both is reported.
- Note (MAD-X): e1 --> e1, e2 --> e2 (a MAD-X sbend measures its pole faces against
  the same sector geometry PALS does). `e1_rect`/`e2_rect` are converted according to
  `ref_geometry`: `ARC`/`CHORD` --> `e = e_rect + angle/2`; `ENTRANCE_COORDS` -->
  `e1 = e1_rect`, `e2 = e2_rect + angle`; `EXIT_COORDS` --> `e1 = e1_rect + angle`,
  `e2 = e2_rect`.
- Note (MAD-X): edge1_int --> `fint = 0.5, hgap = 2*edge1_int`, edge2_int -->
  `fintx`/`hgapx`; h1 --> h1, h2 --> h2; tilt_ref --> tilt.
- Note (MAD-X): a MAD-X sbend is always an arc with vertically pure multipoles, so a
  `ref_geometry` other than `ARC`, or a `multipole_geometry` other than
  `FOLLOWS_REF_GEOMETRY`/`VERTICALLY_PURE`, is reported. `L_sagitta` is an output
  parameter and is an error.
- Note (MAD-X): `Kn0_from_g_ref: false` with no order-0 multipole set gives a bend with
  the reference geometry and no field of its own, which MAD-X — tracking through the
  same `angle` it bends the reference orbit with — cannot express, and is reported.

### BodyShiftP --> AlignmentParams
- x_offset --> x_offset
- y_offset --> y_offset
- z_offset --> z_offset
- x_rot --> x_rot
- y_rot --> y_rot
- z_rot --> tilt

- Note (MAD-X): the whole group becomes an `EALIGN` command, not element attributes:
  x_offset --> dx, y_offset --> dy, z_offset --> ds, x_rot --> -dphi,
  y_rot --> dtheta, z_rot --> dpsi. MAD-X rotates about the entrance of an element
  where PALS rotates about its centre, so the two agree only to first order.

### ElectricMultipoleP --> Not in SciBmad yet

### FloorP --> Calculated

### CoordinateSetP --> Set in floor shift element (to be added to scibmad)
- Note (MAD-X): MAD-X has no element that sets the global coordinates of the reference
  curve, so the group is an error. `FloorShift` and `Fiducial`, the two kinds that
  carry it, have no MAD-X equivalent either.

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
- Note (Bmad): a Bmad bend carries a quadrupole and a sextupole component of its own besides its
  bending field, so a bend's `Kn1` --> `K1` and `Kn2` --> `K2` as well (`Bn1` -->
  `B1_GRADIENT`, `Bn2` --> `B2_GRADIENT`). These two hold a normal field only, and are components
  added to a field the bend already has rather than the strength that makes it a bend, so an
  order with a skew part -- a `Ks1`/`Ks2`, or a `tilt1`/`tilt2` that rotates one into being --
  keeps both parts in the `An`/`Bn` form instead. A bend has no attribute above order 2, so its
  higher multipoles stay `An`/`Bn` either way.
- Note (Bmad): PALS states a bend's field outright, where Bmad states its departure from the
  reference bend. So `Kn0` is translated as `dg = Kn0 - g_ref` -- against `1/radius_ref` when
  the reference bend is given as a radius, and against `Bn0_ref` when the field is not
  normalized. A field equal to the reference bend departs from it by nothing, and no `dg` is
  written. The two flavors cannot be mixed: measuring a `Kn0` against a `Bn0_ref` (or the
  reverse) takes the reference momentum, which belongs to the branch and not to the element.

- Note (MAD-X): a PALS coefficient is a MAD-X coefficient outright — neither carries
  the `1/N!` of the field expansion — so the orders an element owns become:
  `KnN` --> `kN` and `KsN` --> `kNs` for a quadrupole (N=1), sextupole (2) and
  octupole (3); `Kn0` --> `angle`, `Kn1` --> `k1`, `Ks1` --> `k1s`, `Kn2` --> `k2`
  for a bend; `Kn0L` --> `-hkick` and `Ks0L` --> `vkick` for a kicker.
- Note (MAD-X): a `tiltN` is rotated into the normal and skew components, MAD-X's
  own `tilt` being one roll for the whole element rather than one per order.
- Note (MAD-X): a length is put in or taken out to match the attribute — `angle`,
  `hkick` and `vkick` are integrated, the rest are not.
- Note (MAD-X): a MAD-X magnet is strictly single-order. Only a `multipole` element
  has multipole arrays, where each order becomes the integrated `knl[N]`/`ksl[N]`;
  any other order on any other magnet is reported and dropped.
- Note (MAD-X): a `BnN`/`BsN` is divided by the signed rigidity `pals_brho`, MAD-X
  having no field-valued strength attribute.

### MetaP --> MetaParams
- alias --> alias (Bmad: alias)
- label --> label (Bmad: type)
- description --> description (Bmad: descrip)
- ID --> none
- location --> none
- history --> none
- Note: any other (non-standard) component --> none
- Note: a component holding a structure rather than a string is not translated.
- Note (MAD-X): a MAD-X element holds no metadata of its own, so every component
  that is a plain string becomes a comment line above the element definition.

### ParticleP --> Create new bunch
- Note (MAD-X): MAD-X starts a particle with the `START` command of the `TRACK`
  module, which has no place in a lattice file, so the coordinates are written out
  as a comment: x, px, y, py as they stand, `z` --> `t = z / beam->beta` and
  `pz` --> `pt = pz * beam->beta`. Spin has no MAD-X equivalent.

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
- Note (MAD-X): the offsets become `patch_trans = {x, y, z}` and the rotations
  `patch_ang = {x_rot, y_rot, z_rot}` of a `changeref`. MAD-X applies the three
  angles in an order of its own, so the correspondence is exact only to first order
  in the angles. A changeref has no length, and `flexible`, `ref_coords` and
  `user_sets_length` have no equivalent.

### ReferenceP --> Beamline Properties
- species_ref --> species_ref
- pc_ref --> pc_ref
- E_tot_ref --> E_ref
- time_ref --> none
- location --> none
- Note (MAD-X): the group becomes the `BEAM` command: species_ref --> particle
  (positron, electron, proton, antiproton, posmuon, negmuon; anything else has to
  be given its mass and charge by hand), pc_ref --> `pc` and E_tot_ref --> `energy`,
  both in GeV rather than eV.

### ReferenceChangeP --> Beamline Properties
- extra_dtime_ref --> none
- dE_ref --> dE_ref
- E_tot_ref --> E_ref
- species_ref --> species_ref
- Note (MAD-X): MAD-X takes the reference energy from the `BEAM` command and cannot
  change it in mid-line, so the whole group is an error.

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

- Note (MAD-X): frequency --> `freq` in MHz, harmon --> `harmon`,
  voltage --> `volt` in MV, gradient --> `volt = gradient * L_active`.
- Note (MAD-X): phase --> `lag`, offset by what `zero_phase` measures from. MAD-X's
  zero lag is the zero crossing half a period from the one Bmad and PALS call the
  stable point above transition (`phi0 = lag + 0.5`), so
  ABOVE_TRANSITION --> `lag = phase - 0.5`, BELOW_TRANSITION --> `lag = phase`, and
  ACCELERATING --> `lag = phase - 0.25`.
- Note (MAD-X): a TRAVELING_WAVE cavity is MAD-X's `twcavity`, which only PTC
  tracks, so it is translated as an `rfcavity` with a warning; `multipass_phase`,
  `num_cells`, `L_active` and `dE_ref` have no equivalent.

### SolenoidP --> BMultipoleParams
- Ksol --> Ksol
- Bsol --> Bsol
- Note (MAD-X): Ksol --> `ks`, Bsol --> `ks = Bsol / pals_brho`. A solenoid of zero
  length also needs MAD-X's integrated `ksi`, which PALS does not state.

### TrackingP --> UniversalParams.tracking_method
- Note (MAD-X): tracking parameters are program specific by design and are skipped.

### TwissP --> initial conditions
- Note (MAD-X): the group becomes a `BETA0` block. beta_a --> betx,
  beta_b --> bety, alpha_a --> alfx, alpha_b --> alfy, phi_a --> `mux = phi_a/2pi`
  (MAD-X counts the phase in turns), eta_x --> `dx = eta_x / beam->beta`, and
  likewise eta_y, etap_x, etap_y.
- Note (MAD-X): PALS states the Twiss parameters in the a/b normal modes and MAD-X
  in the x/y planes, which are the same thing only when the lattice is uncoupled.
  The coupling itself is Bmad's C matrix here and MAD-X's R matrix there, which are
  different parametrizations, so `cmatNN` is not translated; nor is `deta_x_ds`,
  MAD-X having no dispersion derivative.

### Lattices
- Beamlines --> Beamlines
- To be added: Lattices in PALS --> Lattices
- Note (MAD-X): a BeamLine becomes a `line` and a Lattice becomes the `use, period`
  statement. A leading `BeginningEle` is dropped — it carries the reference parameters,
  which become the `BEAM` command — whether the line spells it out or names it; a line
  that does not begin with one keeps every element it has. MAD-X expands one sequence at a time, so only the first branch is used
  and the rest are commented out. MAD-X has no geometry attribute — whether a branch
  closes on itself is decided by how it is used — so `periodic` becomes a comment.

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
- Note (MAD-X): the same in every respect, MAD-X also resolving a name against what
  is defined above the point of use. A MAD-X variable is a value and nothing else, so
  `absolute_error` and `relative_error` are reported.
- Note (MAD-X): an expression is carried across as it stands — MAD-X's arithmetic and
  ordinary functions are PALS' as well — but two things in one are reported rather
  than rewritten, expression translation being an open item for all the translators:
  the particle-data functions (`mass_of`, `charge_of`, `anomalous_moment_of`), which
  MAD-X does not have, and the predefined constants MAD-X spells differently
  (`c_light` --> `clight`, `e_charge` --> `qelect`, `r_electron` --> `erad`,
  `r_proton` --> `prad`, `mu_0_vac` --> `amu0`) or does not have at all (`h_planck`,
  `hbar`, `k_boltzmann`, `eps_0_vac`, `fine_structure`, `n_avogadro`,
  `classical_radius_factor`). `pi` is the one they agree on.

### Controllers --> MAD-X variables and deferred assignments
- variables --> `name = value;` (global MAD-X variables)
- controls --> `ele->attribute := expression;`
- MetaP --> comment lines above the definitions
- Note (MAD-X): a PALS controller owns its variables, so `ps1>cur` and `ps2>cur` are
  two independent knobs. MAD-X has one namespace for the whole file, so a variable
  whose bare name another controller or a constant also claims is written as
  `<controller>__<variable>`, and the expressions using it are rewritten to match. A
  name nobody else claims keeps its bare form.
- Note (MAD-X): `control_type: ABSOLUTE` sets the attribute outright, which is what a
  deferred assignment does. `RELATIVE` is a knob: the slave keeps the value the lattice
  gave it and moves by how far the knob has turned *from where it started*, so the
  assignment is `ele->attr := <element's own value> + (expr) - (expr at the variables'
  initial settings)`. MAD-X forbids the circular `ele->k1 := ele->k1 + dk`, so the
  element's own value is read back out of the element definition; and the last term —
  which a Bmad `group` keeps track of by itself — is left out only when it can be shown
  to come to zero, which for a knob resting at zero it does.
- Note (MAD-X): the expression is scaled the same way the element attribute was —
  by the length when the attribute and the PALS parameter disagree about
  integration, by `1/pals_brho` when the parameter is a field, by -1 for an `hkick`.
- Note (MAD-X): a control target may name its element by kind, as `{kind}::{name}`;
  the qualifier is checked against the element found and then dropped. A `>>` or `>>>`
  qualifier naming the BeamLine or Lattice an element is reached through has no MAD-X
  equivalent and is an error.
- Note (MAD-X): a control aimed at a multipole array entry has no target — MAD-X
  cannot name one entry of a `knl` — and is an error, as is one aimed at a tilted
  multipole or selecting its slaves by pattern.

### TODO
- translating expression
- names of fundamental constants
- names of functions (tan)
- sinc --> sincu
- MAD-X: `ElectricMultipoleP`, `FloorP`, `ForkP`, `GirderP` and `TaylorP`
