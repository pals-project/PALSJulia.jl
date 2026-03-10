using Documenter
import Pkg
Pkg.activate(joinpath(@__DIR__, ".."))
import pals_julia

makedocs(
    modules = [pals_julia],
    sitename = "pals_julia.jl",
    authors = "Alex He",
    pages = [
        "Home" => "index.md",
    ],
)

deploydocs(
    repo = "github.com/pals-project/pals-julia.git",
)