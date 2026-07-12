# ---------------------------------------------------------------------------
# docs/api/make.jl
#
# Build the API reference (from the package docstrings) with Documenter.jl.
# This produces ONLY the `/api/` portion of the documentation site; the
# narrative docs are built with Sphinx + Furo (see docs/src/). The two outputs
# are combined into gh-pages/ by docs/build.py.
#
# Output lands in docs/api/build/ (Documenter's default, relative to this file).
# ---------------------------------------------------------------------------

using pals_julia
using Documenter

DocMeta.setdocmeta!(pals_julia, :DocTestSetup,
                    :(using pals_julia); recursive = true)

makedocs(;
  modules  = [pals_julia],
  authors  = "Alex He and contributors",
  sitename = "pals-julia API Reference",
  format = Documenter.HTML(;
    canonical = "https://pals-project.github.io/pals-julia/api",
    edit_link = "main",
    assets    = String[],
    # Flat .html files (not pretty dir URLs) so the "← Documentation" redirect
    # and the relative links back to the Sphinx site resolve correctly.
    prettyurls = false,
  ),
  pages = [
    "← Documentation" => "main-docs.md",
    "API Reference"   => "index.md",
  ],
  checkdocs = :exports,
  warnonly  = true,
)

# Deployment is handled by docs/build.py + the docs workflow, which merge this
# output (docs/api/build) into gh-pages/api, so there is no `deploydocs(...)`.
