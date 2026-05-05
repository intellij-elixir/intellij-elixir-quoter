defmodule IntellijElixir.Mixfile do
  use Mix.Project

  def project do
    [
      app: :intellij_elixir,
      deps: deps(),
      description: description(),
      docs: docs(),
      elixir: "~> 1.11",
      package: package(),
      preferred_cli_env: [
        credo: :test,
        dialyzer: :test
      ],
      version: "2.1.0"
    ]
  end

  # Configuration for the OTP application
  #
  # Type `mix help compile.app` for more information
  def application do
    [extra_applications: [:logger], mod: {IntellijElixir, []}]
  end

  # Dependencies can be Hex packages:
  #
  #   {:mydep, "~> 0.3.0"}
  #
  # Or git/path repositories:
  #
  #   {:mydep, git: "https://github.com/elixir-lang/mydep.git", tag: "0.1.0"}
  #
  # Type `mix help deps` for more examples and options
  defp deps do
    [
      {:credo, "1.0.0", only: :test},
      {:dialyxir, "~> 0.5", only: :test, runtime: false},
      {:distillery, "~> 2.0", runtime: false},
      {:ex_doc, "~> 0.19.0", only: [:dev, :test], runtime: false}
    ]
  end

  defp description do
    """
    IntellijElixir allows intellij-elixir to ask Elixir for the native quoted form of code to check that
    intellij-elixir's quoted form matches.
    """
  end

  defp docs do
    [
      extras: extras()
    ]
  end

  defp extras do
    [
      "CHANGELOG.md",
      "LICENSE.md",
      "README.md",
      "UPGRADING.md"
    ]
  end

  defp package do
    [
      file: ["lib", "mix.exs" | extras()],
      licenses: ["Apache 2.0"],
      links: %{
        "Docs" => "https://hexdocs.pm/intellij_elixir",
        "Github" => "https://github.com/KronicDeth/intellij_elixir"
      },
      maintainers: [
        "Luke Imhoff"
      ]
    ]
  end
end
