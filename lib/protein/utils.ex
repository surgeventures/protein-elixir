defmodule Protein.Utils do
  @moduledoc false

  alias Confix
  alias Protein.{AMQPAdapter, HTTPAdapter}

  def get_config(opts, key, default \\ nil) do
    opts
    |> Keyword.get(key, default)
    |> Confix.parse()
  end

  def get_config!(opts, key) do
    opts
    |> Keyword.fetch!(key)
    |> Confix.parse()
  end

  def mocking_enabled? do
    Application.get_env(:protein, :mocking_enabled, Mix.env == :test)
  end

  def resolve_adapter(:amqp), do: AMQPAdapter
  def resolve_adapter(:http), do: HTTPAdapter
  def resolve_adapter(adapter_mod), do: adapter_mod

  def resolve_adapter_server_mod(adapter_mod) do
    :"#{adapter_mod}.Server"
  end

  def resolve_adapter_connection_mod(adapter_mod) do
    :"#{adapter_mod}.Connection"
  end

  def generate_random_id do
    binary = <<
      System.system_time(:nanoseconds)::64,
      :erlang.phash2({node(), self()}, 16_777_216)::24,
      :erlang.unique_integer()::32
    >>

    Base.hex_encode32(binary, case: :lower)
  end

  def atomize_map_keys(map) do
    map
      |> Map.new(fn {key, value} -> {String.to_atom(key), value} end)
  end
end
