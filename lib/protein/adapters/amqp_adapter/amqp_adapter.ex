defmodule Protein.AMQPAdapter do
  @moduledoc """
  Transports RPC calls through AMQP messaging queue.

  ## Usage

  In order to use this adapter in your client, use the following code:

      defmodule MyProject.RemoteRPC do
        use Protein.Client

        transport :amqp,
          url: "amqp://example.com",
          queue: "remote_rpc",
          timeout: 15_000,
          reconnect_interval: 1_000

        # ...
      end

  In order to use this adapter in your server, use the following code:

      defmodule MyProject.MyRPC do
        use Protein.Server

        transport :amqp,
          url: "amqp://example.com",
          queue: "my_rpc",
          concurrency: 5,
          reconnect_interval: 5_000

        # ...
      end

  You can also configure the adapter per environment in your Mix config as follows:

      config :my_project, MyProject.MyRPC,
        transport: [adapter: :amqp,
                    url: {:system, "MY_RPC_AMQP_URL"},
                    queue: {:system, "MY_RPC_AMQP_QUEUE"}]

  """

  alias AMQP.Basic
  alias Protein.{TransportError, Utils}

  @doc false
  def call(request, opts) do
    {chan, response_queue} = get_connection(opts)
    queue = Utils.get_config!(opts, :queue)
    timeout = Utils.get_config(opts, :timeout, 15_000)

    correlation_id = generate_request_id()
    opts = put_expiration([
      reply_to: response_queue,
      correlation_id: correlation_id], timeout)

    Basic.consume(chan, response_queue, nil, no_ack: true)
    Basic.publish(chan, "", queue, request, opts)

    wait_for_response(correlation_id, timeout)
  end

  defp get_connection(opts) do
    opts
    |> Keyword.fetch!(:connection_name)
    |> GenServer.call(:get)
  end

  defp generate_request_id do
    24
    |> :crypto.strong_rand_bytes()
    |> Base.encode64()
  end

  defp put_expiration(opts, nil), do: opts
  defp put_expiration(opts, timeout), do: Keyword.put(opts, :expiration, to_string(timeout))

  defp wait_for_response(correlation_id, timeout) do
    receive do
      {:basic_deliver, "ESRV", %{correlation_id: ^correlation_id}} ->
        raise TransportError, adapter: __MODULE__, context: :service_error
      {:basic_deliver, payload, %{correlation_id: ^correlation_id}} ->
        payload
    after
      timeout || :infinity ->
        raise TransportError, adapter: __MODULE__, context: {:timeout, timeout}
    end
  end

  @doc false
  def push(request, opts) do
    {chan, _} = get_connection(opts)
    queue = Utils.get_config!(opts, :queue)

    Basic.publish(chan, "", queue, request)
  end
end
