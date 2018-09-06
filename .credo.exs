%{
  configs: [
    %{
      name: "default",
      files: %{
        included: ~w{config lib priv test},
        excluded: ["config/dev.secret.exs"]
      },
      strict: true,
      color: true,
      checks: [
        {Credo.Check.Readability.MaxLineLength, max_length: 100},
        {Credo.Check.Warning.RaiseInsideRescue, false}
      ]
    }
  ]
}
