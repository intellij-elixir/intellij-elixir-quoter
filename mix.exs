defmodule IntellijElixir.Mixfile do
  use Mix.Project

  def project do
    [
      app: :quoter,
      deps: deps(),
      description: description(),
      dialyzer: dialyzer(),
      elixir: "~> 1.11",
      package: package(),
      releases: releases(),
      version: "3.0.0"
    ]
  end

  # Configuration for the OTP application
  #
  # Type `mix help compile.app` for more information
  def application do
    [extra_applications: [:logger], mod: {IntellijElixir, []}]
  end

  defp releases do
    [
      quoter: [
        include_erts: true,
        applications: [runtime_tools: :permanent],
        cookie: "intellij-elixir-quoter"
      ]
    ]
  end

  defp dialyzer do
    [
      plt_file: {:no_warn, "priv/plts/dialyzer.plt"}
    ]
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
      # Dev only: neither compiles on the oldest Elixir the quoter supports, where CI still runs the tests.
      {:credo, "~> 1.7", only: :dev, runtime: false},
      {:dialyxir, "~> 1.4", only: :dev, runtime: false}
    ]
  end

  defp description do
    """
    IntellijElixir allows intellij-elixir to ask Elixir for the native quoted form of code to check that
    intellij-elixir's quoted form matches.
    """
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
        "Github" => "https://github.com/intellij-elixir/intellij-elixir-quoter"
      },
      maintainers: [
        "Luke Imhoff"
      ]
    ]
  end
end
