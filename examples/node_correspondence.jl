# Example: mapping corresponding nodes across the four trees of a PALS lattice.
#
# parse_and_expand_pals returns four views of a lattice — `original`,
# `combined`, `expanded` and `leftover`. node_correspondence connects the nodes
# of these views: given any node, it hands back the nodes it corresponds to in
# the others. The correspondence is computed from provenance recorded as the
# trees are derived from one another, so it is exact even where expansion
# duplicates a node (a `repeat`, an `inherit`, a scalar substitution, a fork).

using PALSJulia
import PALSJulia as pj

ex_file = joinpath(@__DIR__, "..", "lattice_files", "ex.pals.yaml")

lat  = pj.parse_and_expand_pals(ex_file)
corr = pj.node_correspondence(lat)

println("Built a correspondence over ", length(corr), " nodes.\n")

# ── A node outside the lattice is left over, not expanded ─────────────────────
# 'a_const' is defined at the top level of the facility and the lattice never
# refers to it, so expansion leaves it behind: it appears once in `original`,
# once in `combined` and once in `leftover`, and not at all in `expanded`.
a_const = lat.combined["PALS"]["facility"][1]["constants"]["a_const"]
entry   = corr[a_const]

println("Correspondence of the 'a_const' node:")
println("  in original: ", [pj.to_yaml_string(n) for n in entry.original])
println("  in combined: ", [pj.to_yaml_string(n) for n in entry.combined])
println("  in leftover: ", [pj.to_yaml_string(n) for n in entry.leftover])
println("  in expanded: ", [pj.to_yaml_string(n) for n in entry.expanded], "  (empty)")
println()

# The map can be queried from *any* of the four trees and returns the same
# equivalence class — here we start from the node in the original tree.
@assert corr[entry.original[1]] == entry
println("Looking the class up from the original node gives the same result.\n")

# ── A node duplicated by expansion maps one-to-many ───────────────────────────
# Find a combined node that expansion turned into several expanded copies (for
# ex.pals.yaml this is the 'repeat'ed sub-line unrolled inside inj_line).
one_to_many = nothing
for (node, e) in corr
  if length(e.combined) == 1 && node == e.combined[1] && length(e.expanded) > 1
    global one_to_many = e
    break
  end
end

if one_to_many !== nothing
  println("A combined node that expansion duplicated:")
  println("  combined source: ", pj.to_yaml_string(one_to_many.combined[1]))
  println("  → ", length(one_to_many.expanded), " corresponding expanded nodes.")
end
