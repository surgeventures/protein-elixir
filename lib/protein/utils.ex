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

  def resolve_adapter_client_mod(adapter_mod) do
    :"#{adapter_mod}.Client"
  end
end
