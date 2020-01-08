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
    {chan, response_queue} = connect(opts)
    responders = :ets.new(:responders, [])
    {:ok, {chan, response_queue, responders, opts}}
  end

  def handle_call(:get_channel_and_response_queue, _from, state = {chan, response_queue, _, _}) do
    {:reply, {chan, response_queue}, state}
  end

  def handle_call({:responder_register, id, timeout}, {pid, _}, state = {_, _, responders, _}) do
    :ets.insert(responders, {id, pid})
    Process.send_after(self(), {:responder_timeout, id}, timeout)
    {:reply, :ok, state}
  end

  def handle_info({:basic_consume_ok, _meta}, state), do: {:noreply, state}
  def handle_info({:basic_cancel, _meta}, state), do: {:stop, :normal, state}
  def handle_info({:basic_cancel_ok, _meta}, state), do: {:noreply, state}

  def handle_info({:basic_deliver, payload, %{correlation_id: id}}, state = {_, _, responders, _}) do
    case :ets.lookup(responders, id) do
      [{^id, pid}] ->
        send(pid, {:response, payload})
        :ets.delete(responders, id)

      _ ->
        nil
    end

    {:noreply, state}
  end

  def handle_info({:DOWN, _, :process, _pid, _reason}, {_, _, opts}) do
    {chan, response_queue} = connect(opts)
    {:noreply, {chan, response_queue, opts}}
  end

  def handle_info({:responder_timeout, id}, state = {_, _, responders, _}) do
    :ets.delete(responders, id)
    {:noreply, state}
  end

  defp connect(opts) do
    url = Utils.get_config!(opts, :url)
    reconnect_int = Utils.get_config(opts, :reconnect_interval, 1_000)

    case init_conn_chan(url) do
      {:ok, conn, chan} ->
        Process.monitor(conn.pid)
        {:ok, %{queue: response_queue}} = Queue.declare(chan, "", exclusive: true)
        {:ok, _consumer_tag} = Basic.consume(chan, response_queue, nil, no_ack: true)
        {chan, response_queue}

      :error ->
        Logger.error("Connection to #{url} failed, reconnecting in #{reconnect_int}ms")
        :timer.sleep(reconnect_int)
        connect(opts)
    end
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
