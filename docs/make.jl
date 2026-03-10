using Documenter

push!(LOAD_PATH, "../src/")
import Pkg
Pkg.activate(joinpath(@__DIR__, ".."))
import pals_julia as pj

makedocs(
    sitename = "pals_julia.jl",
    authors = "Alex He",
    format = Documenter.HTMLWriter.HTML(
        prettyurls = get(ENV, "CI", nothing) == "true",  # Use pretty URLs on CI
        assets = String[],
    ),
    pages = [
        "Home" => "index.md",
    ],
)

deploydocs(
    repo = "https://github.com/pals-project/pals-julia",
)