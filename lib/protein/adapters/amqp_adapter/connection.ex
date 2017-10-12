defmodule Protein.AMQPAdapter.Connection do
  @moduledoc false

  use AMQP
  use GenServer
  require Logger
  alias AMQP.{Connection, Queue}
  alias Protein.Utils

  def start_link(opts) do
    name = Keyword.fetch!(opts, :connection_name)
    GenServer.start_link(__MODULE__, opts, name: name)
  end

  def init(opts) do
    chan = connect(opts)
    response_queue = create_response_queue(chan)

    {:ok, {chan, response_queue, opts}}
  end

  def get(connection_name) do
    GenServer.call(connection_name, :get)
  end

  def handle_call(:get, _from, state = {chan, response_queue, _opts}) do
    {:reply, {chan, response_queue}, state}
  end

  def handle_info({:basic_consume_ok, _meta}, state), do: {:noreply, state}
  def handle_info({:basic_cancel, _meta}, state), do: {:stop, :normal, state}
  def handle_info({:basic_cancel_ok, _meta}, state), do: {:noreply, state}
  def handle_info({:DOWN, _, :process, _pid, _reason}, {_, _, opts}) do
    chan = connect(opts)
    response_queue = create_response_queue(chan)

    {:noreply, {chan, response_queue, opts}}
  end

  defp connect(opts) do
    url = Utils.get_config!(opts, :url)
    reconnect_int = Utils.get_config(opts, :reconnect_interval, 1_000)

    case init_conn_chan(url) do
      {:ok, conn, chan} ->
        Process.monitor(conn.pid)
        chan
      :error ->
        Logger.error(fn -> "Connection to #{url} failed, reconnecting in #{reconnect_int}ms" end)
        :timer.sleep(reconnect_int)
        connect(opts)
    end
  end

  defp create_response_queue(chan) do
    {:ok, %{queue: response_queue}} = Queue.declare(chan, "", exclusive: true)
    response_queue
  end

  defp init_conn_chan(url) do
    case Connection.open(url) do
      {:ok, conn} ->
        {:ok, chan} = Channel.open(conn)
        {:ok, conn, chan}
      {:error, _} ->
        :error
    end
  end
end
