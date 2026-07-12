# Translating to SciBmad and Bmad

PALSJulia can translate a PALS-format lattice into the two Cornell accelerator
formats:

- **`src/toSciBmad.jl`** — emits a [SciBmad](https://github.com/bmad-sim/SciBmad.jl)
  / [Beamlines](https://github.com/bmad-sim/Beamlines.jl) description.
- **`src/toBmad.jl`** — emits a classic [Bmad](https://www.classe.cornell.edu/bmad/)
  lattice.

Both translators read a lattice with `get_lattices`,
walk the expanded element list, and map each PALS element and its parameters
onto the corresponding target-format element.

## Running the translators

Each translator is a runnable script. `toSciBmad.jl` translates the built-in
example lattice, while `toBmad.jl` takes a lattice directory as its first
argument:

```console
julia src/toSciBmad.jl
julia src/toBmad.jl lattice_files
```

## Element and parameter mapping

PALS element kinds and their parameters do not map one-to-one onto Bmad. The
translators encode the conversions — renamed parameters, unit changes, and
cases that have no equivalent (and are skipped with a warning). For example,
an `ApertureP` becomes a Bmad `ApertureParams`, with `x_min`/`x_max` mapped to
`x1_limit`/`x2_limit` (or derived from `x_center`/`x_width`).

The complete, element-by-element list of these mappings is maintained in
[`docs/translation_notes.md`](https://github.com/pals-project/PALSJulia/blob/main/docs/translation_notes.md)
in the repository. Consult it when adding support for a new element or when a
parameter comes through untranslated.

## Extending a translator

To add support for a new element or parameter:

1. Find its PALS definition and decide on the target-format equivalent; record
   it in `docs/translation_notes.md`.
2. Add the mapping to `make_ele_str` (and the helpers it calls, such as
   `make_init_str` and `make_bl_str`) in the relevant translator.
3. Translate a lattice that exercises the element and check the output.
