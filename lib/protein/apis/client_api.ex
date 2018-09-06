defmodule Protein.ClientAPI do
  @moduledoc """
  Functions for making client requests to remote services.
  """

  defmacro __using__(_) do
    quote do
      alias Protein.Utils

      @doc """
      Calls a responding service that is expected to potentially reject the request.
      """
      def call(request_struct) do
        apply_client(request_struct, :call)
      end

      @doc """
      Calls a responding service that is not expected to reject the request.
      """
      def call!(request_struct) do
        apply_client(request_struct, :call!)
      end

      @doc """
      Pushes a request to a non-responding service.
      """
      def push(request_struct) do
        apply_client(request_struct, :push)
      end

      defp apply_client(request_struct = %{__struct__: request_mod}, method) do
        transport_opts = get_transport_opts()
        service_opts = __MODULE__.__service_opts__(request_mod)

        ensure_connection_started(transport_opts)

        apply(Protein.Client, method, [request_struct, service_opts, transport_opts])
      end

      def get_transport_opts do
        transport_opts = __MODULE__.__transport_opts__()
        adapter = Keyword.fetch!(transport_opts, :adapter)
        adapter_mod = Utils.resolve_adapter(adapter)
        connection_mod = Utils.resolve_adapter_connection_mod(adapter_mod)
        connection_name = :"#{__MODULE__}.Connection"

        Keyword.merge(
          transport_opts,
          connection_mod: connection_mod,
          connection_name: connection_name
        )
      end

      def ensure_connection_started(opts) do
        import Supervisor.Spec

        mod = Keyword.fetch!(opts, :connection_mod)

        if Code.ensure_loaded?(mod) && !Utils.mocking_enabled?() do
          pid = Process.whereis(__MODULE__)
          spec = worker(mod, [opts])

          case Supervisor.start_child(pid, spec) do
            {:ok, _} -> nil
            {:error, {:already_started, _}} -> nil
            {:error, error} -> raise("Error starting client: #{inspect(error)}")
          end
        end
      end
    end
  end

  @doc """
  Calls a responding service that is expected to potentially reject the request.
  """
  def call(_request_struct) do
    raise("This function must be called on modules that use #{inspect(__MODULE__)}")
  end

  @doc """
  Calls a responding service that is not expected to reject the request.
  """
  def call!(_request_struct) do
    raise("This function must be called on modules that use #{inspect(__MODULE__)}")
  end

  @doc """
  Pushes a request to a non-responding service.
  """
  def push(_request_struct) do
    raise("This function must be called on modules that use #{inspect(__MODULE__)}")
  end
end
