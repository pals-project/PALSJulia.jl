# Example: finding named constructs by name.
#
# match_names implements PALS name matching:
#
#   [{lattice}>>>][{branch}>>][{kind}::]{name}[>{group}.{sub}. … .{parameter}]
#
# {lattice}, {branch}, {name} are PCRE2 patterns (anchored whole-name matches);
# {kind} and the dotted parameter path are matched exactly. It returns the nodes
# the string resolves to — elements, parameter groups, parameters, constants, or
# variables — which live in the tree you searched. Elements are searched for in
# the `expanded` view; constants and variables are not part of the lattice, so
# they are found in `leftover`.

using PALSJulia
import PALSJulia as pj

ex_file = joinpath(@__DIR__, "..", "lattice_files", "ex.pals.yaml")
lat = pj.parse_and_expand_pals(ex_file)

# Print a node as "key = value", omitting the value for container nodes.
label(n) = (pj.is_map(n) || pj.is_sequence(n)) ? pj.node_key(n) :
           "$(pj.node_key(n)) = $(String(n))"

show_matches(q; tree = lat.expanded) = begin
  m = pj.match_names(tree, q)
  println("  \"", q, "\"  →  ", length(m), " match(es)")
  for n in m
    println("      ", label(n))
  end
end

# ── Element parameters ────────────────────────────────────────────────────────
println("Element parameters:")
show_matches("Q1a>length")               # a named element's length
show_matches("Quadrupole::.*>length")    # restrict to a kind with `::`
show_matches("lat1>>>Q1a>length")        # restrict to a lattice with `>>>`

# ── Whole elements ────────────────────────────────────────────────────────────
# Drop the parameter path to match the element node itself.
println("\nElements:")
show_matches("Q1a")

# ── Constants and variables ───────────────────────────────────────────────────
# A bare name also matches constants/variables by name. These are defined at
# facility level rather than inside the lattice, so search the leftover view.
println("\nConstants and variables:")
show_matches("a_const"; tree = lat.leftover)
show_matches(".*_var"; tree = lat.leftover)

# ── Editing matched parameters in place ───────────────────────────────────────
# The returned nodes belong to lat.expanded, so they can be modified directly.
println("\nEditing in place:")
for n in pj.match_names(lat.expanded, "Q1a>direction")
  pj.set_scalar!(n, "1")
end
show_matches("Q1a>direction")
