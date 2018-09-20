defmodule Protein.ServerAPI do
  @moduledoc """
  functions for handling service calls.
  """

  defmacro __using__(_) do
    quote do
      alias Protein.{RequestPayload, Server}

      @doc """
      Processes a request by calling appropriate service.

      Under normal circumstances, the server is invoked by traffic from the transport layer and not
      directly. Still, you can make it process a request by bypassing the transport and invoking
      this function directly. It takes the request payload (that would normally come via transport
      layer) as argument and returns response payload (that would normally get returned via
      transport layer) or nil (for non-responding services).
      """
      def process(request) do
        {service_name, request_buf, request_metadata} = RequestPayload.decode(request)
        service_opts = __MODULE__.__service_opts__(service_name)

        Server.process(request_buf, request_metadata, service_opts)
      end
    end
  end

  @doc """
  Processes a request by calling appropriate service.

  Under normal circumstances, the server is invoked by traffic from the transport layer and not
  directly. Still, you can make it process a request by bypassing the transport and invoking
  this function directly. It takes the request payload (that would normally come via transport
  layer) as argument and returns response payload (that would normally get returned via
  transport layer) or nil (for non-responding services).
  """
  def process(_request) do
    raise("This function must be called on modules that use #{inspect(__MODULE__)}")
  end
end
