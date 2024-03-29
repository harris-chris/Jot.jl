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
      "Examples" => "Examples.md",
      "Managing Lambdas" => "Managing_lambdas.md",
      "Labels" => "Labels.md",
      "Function Performance" => "Function_Performance.md",
      "Debugging Functions" => "Debugging_Functions.md",
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
