defmodule Mix.Tasks.Protein.Server do
  use Mix.Task

  @shortdoc "Starts the Protein servers"

  @moduledoc """
  Starts the application by configuring all Protein servers to run.
  """

  @doc false
  def run(args) do
    Application.put_env(:protein, :serve, true, persistent: true)
    Mix.Tasks.Run.run run_args() ++ args
  end

  defp run_args do
    if iex_running?(), do: [], else: ["--no-halt"]
  end

  defp iex_running? do
    Code.ensure_loaded?(IEx) and IEx.started?
  end
end
