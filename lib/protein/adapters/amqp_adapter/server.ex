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
    state = %{channel: chan, opts: opts, consumers: []}
    {:ok, state}
  end

  def terminate(_reason, %{consumers: consumers}) do
    wait_for_all_consumers(consumers)
  end

  defp wait_for_all_consumers([]), do: :ok

  defp wait_for_all_consumers(consumers) do
    receive do
      {:DOWN, _, :process, down_pid, :normal} ->
        present_consumers = Enum.filter(consumers, fn %{pid: pid} -> pid != down_pid end)
        wait_for_all_consumers(present_consumers)

      _ ->
        wait_for_all_consumers(consumers)
    end
  end

  def handle_info({:basic_consume_ok, _meta}, state), do: {:noreply, state}
  def handle_info({:basic_cancel, _meta}, state), do: {:stop, :normal, state}
  def handle_info({:basic_cancel_ok, _meta}, state), do: {:noreply, state}

  def handle_info(
        {:basic_deliver, payload, meta},
        state = %{
          channel: chan,
          opts: opts,
          consumers: consumers
        }
      ) do
    {pid, ref} = spawn_monitor(fn -> consume(chan, opts, meta, payload) end)
    {:noreply, %{state | consumers: consumers ++ [%{pid: pid, meta: meta, monitor_ref: ref}]}}
  end

  # AQMP connection down
  def handle_info(
        {:DOWN, _, :process, pid, _reason},
        state = %{channel: %Channel{conn: %Connection{pid: pid}}, consumers: consumers, opts: opts}
      ) do
    kill_consumers(consumers)
    chan = connect(opts)
    {:noreply, %{state | channel: chan, consumers: []}}
  end

  # handles consumer normal exit
  def handle_info({:DOWN, _, :process, down_pid, :normal}, state = %{consumers: consumers}) do
    {_consumer, remaining_consumers} = get_consumer(consumers, down_pid)
    {:noreply, %{state | consumers: remaining_consumers}}
  end

  # handles consumer error
  def handle_info(
        {:DOWN, _, :process, down_pid, _reason},
        state = %{channel: chan, consumers: consumers}
      ) do
    {%{meta: meta}, remaining_consumers} = get_consumer(consumers, down_pid)
    handle_consumer_error(chan, meta)
    {:noreply, %{state | consumers: remaining_consumers}}
  end

  defp connect(opts) do
    url = Utils.get_config!(opts, :url)
    queue = Utils.get_config!(opts, :queue)

    case init_conn_chan_queue(url, queue) do
      {:ok, conn, chan} ->
        concurrency = Utils.get_config(opts, :concurrency, 5)
        Process.monitor(conn.pid)
        :ok = Basic.qos(chan, prefetch_count: concurrency)
        {:ok, _consumer_tag} = Basic.consume(chan, queue)

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

        if custom_error_logger = Application.get_env(:protein, :custom_error_logger),
          do: custom_error_logger.(error_message)

        Logger.error(error_message)
        :timer.sleep(reconnect_int)
        connect(opts)
    end
  end

  defp init_conn_chan_queue(url, queue) do
    case Connection.open(url) do
      {:ok, conn} ->
        {:ok, chan} = Channel.open(conn)

        chan =
          try do
            {:ok, _} = Queue.declare(chan, queue, durable: true)
            Logger.info("Declared queue #{queue} as durable")
            chan
          catch
            :exit, reason = {{:shutdown, {:server_initiated_close, 406, _message}}, _} ->
              Logger.debug(inspect(reason))

              {:ok, chan} = Channel.open(conn)
              {:ok, _} = Queue.declare(chan, queue, durable: false)
              Logger.info("Declared queue #{queue} as non-durable (fallback-mode)")
              chan
          end

        {:ok, conn, chan}

      {:error, _} ->
        :error
    end
  end

  defp consume(chan, opts, meta, payload) do
    server_mod = Keyword.fetch!(opts, :server_mod)
    response = server_mod.process(payload)
    if should_respond(response, meta), do: respond(response, chan, meta)
    Basic.ack(chan, meta.delivery_tag)
  end

  defp handle_consumer_error(chan, meta) do
    if should_respond("ESRV", meta), do: respond("ESRV", chan, meta)
    Basic.ack(chan, meta.delivery_tag)
  end

  defp kill_consumers(consumers) do
    Enum.each(consumers, fn %{pid: pid, monitor_ref: ref} ->
      Process.demonitor(ref)
      Process.exit(pid, :kill)
    end)
  end

  defp get_consumer(consumers, searched_pid) do
    [consumer] = Enum.filter(consumers, fn %{pid: pid} -> pid == searched_pid end)
    remaining_consumers = Enum.filter(consumers, fn %{pid: pid} -> pid != searched_pid end)
    {consumer, remaining_consumers}
  end

  defp should_respond(nil, _meta), do: false
  defp should_respond(_response, _meta = %{reply_to: :undefined}), do: false
  defp should_respond(_response, _meta), do: true

  defp respond(response, chan, meta) do
    %{
      correlation_id: correlation_id,
      reply_to: reply_to
    } = meta

    :ok = Basic.publish(chan, "", reply_to, response, correlation_id: correlation_id)
  end
end
