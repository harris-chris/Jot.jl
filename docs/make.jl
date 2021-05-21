using Documenter, Jot, Pkg

makedocs(
  sitename = "Jot Documentation",
  format = Documenter.HTML(
      prettyurls = get(ENV, "CI", nothing) == "true"
  ),
  pages = [
    "Home" => "index.md",
    "Manual" => [
      "Guide" => "Guide.md",
      "Examples" => "Examples.md"
    ],
    "API" => [
      "Functions" => "Functions.md",
      "Types" => "Types.md",
    ]
  ],
)

deploydocs(
  repo = "github.com/harris-chris/Jot.jl.git",
  devbranch = "main",
)
