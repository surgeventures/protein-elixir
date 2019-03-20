defmodule Protein.AMQPAdapter.Server do
  @moduledoc false

  use AMQP
  use GenServer, type: :supervisor
  require Logger
  alias AMQP.{Basic, Channel, Connection, Queue}
  alias Protein.Utils

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, [])
  end

  def init(opts) do
    Process.flag(:trap_exit, true)
    chan = connect(opts)
    {:ok, {chan, opts, 0}}
  end

  def terminate(_reason, {_chan, _opts, running_processes_count}) do
    wait_for_all_processes(running_processes_count)
  end

  def wait_for_all_processes(0), do: :ok

  def wait_for_all_processes(running_processes_count) do
    receive do
      {:DOWN, _, :process, _, :normal} -> wait_for_all_processes(running_processes_count - 1)
      _ -> wait_for_all_processes(running_processes_count)
    end
  end

  def handle_info({:basic_consume_ok, _meta}, state), do: {:noreply, state}
  def handle_info({:basic_cancel, _meta}, state), do: {:stop, :normal, state}
  def handle_info({:basic_cancel_ok, _meta}, state), do: {:noreply, state}

  def handle_info({:basic_deliver, payload, meta}, {chan, opts, processes}) do
    pid = spawn(fn -> consume(chan, opts, meta, payload) end)
    Process.monitor(pid)
    {:noreply, {chan, opts, processes + 1}}
  end

  def handle_info(
        {:DOWN, _, :process, pid, _reason},
        {%Channel{conn: %Connection{pid: pid}}, opts, _}
      ) do
    chan = connect(opts)
    {:noreply, {chan, opts, 0}}
  end

  def handle_info({:DOWN, _, :process, _pid, :normal}, {chan, opts, count}) do
    {:noreply, {chan, opts, count - 1}}
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

          "Serving #{inspect(server_mod)} with AMQP from #{queue} at #{url} (concurrency: #{
            concurrency
          })"
        end)

        chan

      :error ->
        reconnect_int = Utils.get_config(opts, :reconnect_interval, 5_000)
        error_message = "Connection to #{url} failed, reconnecting in #{reconnect_int}ms"

        if custom_error_logger = Application.get_env(:protein, :custom_error_logger) do
          custom_error_logger.(error_message)
        end

        Logger.error(error_message)
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

    if should_respond(response, meta), do: respond(response, chan, meta)

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
      stacktrace = System.stacktrace()
      {"ESRV", {exception, stacktrace}}
  end

  defp should_respond(nil, _meta), do: false
  defp should_respond(_response, _meta = %{reply_to: :undefined}), do: false
  defp should_respond(_response, _meta), do: true

  defp respond(response, chan, meta) do
    %{
      correlation_id: correlation_id,
      reply_to: reply_to
    } = meta

    Basic.publish(chan, "", reply_to, response, correlation_id: correlation_id)
  end
end
