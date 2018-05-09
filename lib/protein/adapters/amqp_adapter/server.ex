defmodule Protein.AMQPAdapter.Server do
  @moduledoc false

  use AMQP
  use GenServer
  require Logger
  alias AMQP.{Basic, Channel, Connection, Queue}
  alias Protein.Utils

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, [])
  end

  def init(opts) do
    chan = connect(opts)
    {:ok, {chan, opts}}
  end

  def handle_info({:basic_consume_ok, _meta}, state), do: {:noreply, state}
  def handle_info({:basic_cancel, _meta}, state), do: {:stop, :normal, state}
  def handle_info({:basic_cancel_ok, _meta}, state), do: {:noreply, state}
  def handle_info({:basic_deliver, payload, meta}, state = {chan, opts}) do
    spawn fn -> consume(chan, opts, meta, payload) end
    {:noreply, state}
  end
  def handle_info({:DOWN, _, :process, _pid, _reason}, {_, opts}) do
    chan = connect(opts)
    {:noreply, {chan, opts}}
  end

  defp connect(opts) do
    url = Utils.get_config!(opts, :url)
    queue = Utils.get_config!(opts, :queue)

    case init_conn_chan_queue(url, queue) do
      {:ok, conn, chan} ->
        concurrency = Utils.get_config(opts, :concurrency, 5)
        Process.monitor(conn.pid)
        Basic.qos(chan, prefetch_count: concurrency)
        Basic.consume(chan, queue)
        Logger.info(fn ->
          server_mod = Keyword.fetch!(opts, :server_mod)
          "Serving #{inspect(server_mod)} with AMQP from #{queue} at #{url} (concurrency: #{concurrency})"
        end)
        chan
      :error ->
        reconnect_int = Utils.get_config(opts, :reconnect_interval, 5_000)
        Logger.error(fn ->
          "Connection to #{url} failed, reconnecting in #{reconnect_int}ms"
        end)
        :timer.sleep(reconnect_int)
        connect(opts)
    end
  end

  defp init_conn_chan_queue(url, queue) do
    case Connection.open(url) do
      {:ok, conn} ->
        {:ok, chan} = Channel.open(conn)
        Queue.declare(chan, queue)
        {:ok, conn, chan}
      {:error, _} ->
        :error
    end
  end

  defp consume(chan, opts, meta, payload) do
    server_mod = Keyword.fetch!(opts, :server_mod)

    {response, error} = try_process(payload, server_mod)
    respond(response, chan, meta)
    Basic.ack(chan, meta.delivery_tag)

    if error do
      {exception, stacktrace} = error
      reraise(exception, stacktrace)
    end
  end

  defp try_process(payload, server_mod) do
    response = server_mod.process(payload)
    {response, nil}
  rescue
    exception ->
      stacktrace = System.stacktrace
      {"ESRV", {exception, stacktrace}}
  end

  defp respond(nil, _chan, _meta), do: nil
  defp respond(response, chan, meta) do
    %{
      correlation_id: correlation_id,
      reply_to: reply_to
    } = meta

    Basic.publish(chan, "", reply_to, response, correlation_id: correlation_id)
  end
end
