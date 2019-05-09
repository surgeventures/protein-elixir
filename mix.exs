defmodule Protein.Mixfile do
  use Mix.Project

  def project do
    [
      app: :protein,
      version: "0.17.0",
      elixir: "~> 1.4",
      elixirc_paths: elixirc_paths(Mix.env()),
      build_embedded: Mix.env() == :prod,
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      package: package(),
      aliases: aliases(),
      test_coverage: [tool: ExCoveralls],
      preferred_cli_env: [
        check: :test,
        coveralls: :test,
        "coveralls.detail": :test,
        "coveralls.html": :test
      ],
      name: "Protein",
      description: "Multi-platform remote procedure call (RPC) system based on Protocol Buffers",
      source_url: "https://github.com/surgeventures/protein-elixir",
      homepage_url: "https://github.com/surgeventures/protein-elixir",
      docs: [main: "readme", extras: ["README.md"]]
    ]
  end

  defp package do
    [
      maintainers: ["Karol Słuszniak"],
      licenses: ["MIT"],
      links: %{
        "GitHub" => "https://github.com/surgeventures/protein-elixir"
      },
      files: ~w(mix.exs lib LICENSE.md README.md)
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  defp aliases do
    [
      check: check_alias()
    ]
  end

  defp deps do
    [
      {:amqp, "~> 0.2"},
      {:confix, "~> 0.3"},
      {:credo, "~> 0.10", only: [:dev, :test]},
      {:ex_doc, "~> 0.19", only: :dev, runtime: false},
      {:excoveralls, "~> 0.8", only: :test},
      {:exprotobuf, "~> 1.2"},
      {:httpoison, "~> 0.13"},
      {:mock, "~> 0.2.1", only: :test},
      {:poison, "~> 2.0 or ~> 3.0"}
    ]
  end

  defp check_alias do
    [
      "compile --warnings-as-errors --force",
      "test",
      "credo --strict"
    ]
  end
end
