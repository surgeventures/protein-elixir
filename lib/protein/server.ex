defmodule Protein.Server do
  @moduledoc """
  Responds to service calls from remote systems.

  ## Usage

  Here's how your RPC server module may look like:

      defmodule MyProject.MyRPC do
        use Protein.Server

        # then, declare services with a convention driven config
        proto :create_user

        # ...or with custom proto file name (equivalent of previous call above)
        proto Path.expand("./proto/create_user.proto", __DIR__)

        # ...or with a completely custom config (equivalent of previous calls above)
        service proto: [from: Path.expand("./proto/create_user.proto", __DIR__)],
                service_name: "create_user",
                proto_mod: __MODULE__.CreateUser
                request_mod: __MODULE__.CreateUser.Request,
                response_mod: __MODULE__.CreateUser.Response,
                service_mod: __MODULE__.CreateUserService
      end

  Make sure to add it to the supervision tree in `application.ex` as follows:

      defmodule MyProject.Application do
        use Application

        def start(_type, _args) do
          import Supervisor.Spec

          children = [
            supervisor(MyProject.Repo, []),
            supervisor(MyProject.Web.Endpoint, []),
            # ...
            supervisor(MyProject.MyRPC, []),
          ]

          opts = [strategy: :one_for_one, name: MyProject.Supervisor]
          Supervisor.start_link(children, opts)
        end
      end

  ### Macros and functions

  By invoking `use Protein.Client`, you include the following in your client module:

  - `Protein.RouterAPI`: macros for defining a list of services and transport options
  - `Protein.ServerAPI`: functions for handling service calls
  - `Protein.ClientAPI`: functions for making client requests to remote services

  The inclusion of `Protein.ClientAPI` basically means that every Protein server also includes its
  own client. This gives a free, useful tool for calling the server. It comes at no cost since
  client side of things shares the transport and service config with the server. It also won't
  consume extra resources and won't spawn connection processes until the first client call.

  ## Serving

  By default, the actual server process is not started. In order to start it, you can either invoke
  the `Mix.Tasks.Protein.Server` task or set the `serve` config flag to `true`.

  ### Defining services

  After implementing the server and adding services/protos to it, you need to implement a module set
  via the `service_mod` option. The service should implement a `call/1` function that consumes the
  request structure. In case of responding services (recognized by presence of Response structure),
  the `call/1` function must either return one of supported resolution or rejection values, as
  presented on the example below. In case of non-responding services (recognized by lack of Response
  structure), the return value doesn't matter.

      # test/support/my_project/my_rpc/create_user_service.ex

      alias MyProject.MyRPC.CreateUser.{Request, Response}

      defmodule MyProject.MyRPC.CreateUserMock do
        # with default response
        def call(request = %Request{) do
          :ok
        end

        # ...or with specific response
        def call(request = %Request{}) do
          {:ok, %Response{}}
        end

        # ...or with default error
        def call(request = %Request{}) do
          :error
        end

        # ...or with specific error code
        def call(request = %Request{}) do
          {:error, :something_happened}
        end

        # ...or with specific error message
        def call(request = %Request{}) do
          {:error, "Something went wrong"}
        end

        # ...or with error related to specific part of the request
        def call(request = %Request{}) do
          {:error, {:specific_arg_error, struct: "user", struct: "images", repeated: 0}}
        end

        # ...or with multiple errors (all above syntaxes are supported)
        def call(request = %Request{}) do
          {:error, [
            :something_happened,
            "Something went wrong",
            {:specific_arg_error, struct: "user", struct: "images", repeated: 0}
          ]}
        end
      end

  """

  require Logger
  alias Protein.{ResponsePayload, Utils}

  defmacro __using__(_) do
    quote do
      use Protein.{RouterAPI, ServerAPI, ClientAPI}
      use Supervisor
      require Logger
      alias Protein.{Server, Transport}

      def start_link(_opts \\ []) do
        Supervisor.start_link(__MODULE__, [], name: __MODULE__)
      end

      def init(_) do
        serve = Application.get_env(:protein, :serve) || false
        children = if serve, do: get_server_children(), else: []

        Supervisor.init(children, strategy: :one_for_one)
      end

      defp get_server_children do
        transport_opts = __transport_opts__()

        transport_server_mod =
          transport_opts
          |> Keyword.fetch!(:adapter)
          |> Utils.resolve_adapter()
          |> Utils.resolve_adapter_server_mod()

        transport_server_opts = Keyword.put(transport_opts, :server_mod, __MODULE__)

        [{transport_server_mod, transport_server_opts}]
      end
    end
  end

  @doc false
  def process(request_buf, request_metadata, service_opts) do
    request_metadata =
      Map.put(request_metadata, :request_arrival_timestamp, :os.system_time(:millisecond))

    service_name = Keyword.fetch!(service_opts, :service_name)
    service_mod = Keyword.fetch!(service_opts, :service_mod)
    request_mod = Keyword.fetch!(service_opts, :request_mod)
    response_mod = Keyword.fetch!(service_opts, :response_mod)
    request_type = detect_request_type(response_mod)

    case request_type do
      :call ->
        response =
          log_process(request_type, request_metadata, service_name, fn ->
            process_service(service_mod, request_buf, request_metadata, request_mod, response_mod)
          end)

        ResponsePayload.encode(response)

      :push ->
        log_process(:push, request_metadata, service_name, fn ->
          process_service(service_mod, request_buf, request_mod)
        end)

        nil
    end
  end

  @doc false
  def process_service(service_mod, request_buf, request_mod) do
    request_buf
    |> request_mod.decode()
    |> service_mod.call()
  end

  @doc false
  def process_service(service_mod, request_buf, request_metadata, request_mod, response_mod) do
    {status, response_payload} =
      case process_service(service_mod, request_buf, request_mod) do
        :ok ->
          {:ok, response_mod.encode(response_mod.new())}

        {:ok, response_struct} ->
          {:ok, response_mod.encode(response_struct)}

        :error ->
          {:error, [error: nil]}

        {:error, errors} when is_list(errors) ->
          {:error, Enum.map(errors, &normalize_error/1)}

        {:error, error} ->
          {:error, [normalize_error(error)]}
      end

    {status, response_payload, generate_response_metadata(request_metadata)}
  end

  defp generate_response_metadata(request_metadata) do
    response_metadata = %{
      response_timestamp: :os.system_time(:millisecond)
    }

    Map.merge(request_metadata, response_metadata)
  end

  defp normalize_error(reason) when is_atom(reason) or is_binary(reason), do: {reason, nil}
  defp normalize_error({reason, pointer}), do: {reason, pointer}

  defp detect_request_type(response_mod) do
    case Code.ensure_loaded(response_mod) do
      {:module, _} -> :call
      _ -> :push
    end
  end

  defp log_process(kind, request_metadata = %{}, service_name, process_func) do
    log_with_metadata(fn -> "Processing RPC #{kind}: #{service_name}" end, request_metadata)
    log_request_transport_duration(request_metadata)

    start_time = :os.system_time(:millisecond)
    result = process_func.()
    duration_ms = :os.system_time(:millisecond) - start_time

    status_text =
      case {kind, result} do
        {:push, _} -> "Processed"
        {:call, {:ok, _}} -> "Resolved"
        {:call, _} -> "Rejected"
      end

    log_with_metadata(fn -> "#{status_text} in #{duration_ms}ms" end, request_metadata)

    result
  end

  defp log_with_metadata(log_entry, metadata = %{}) do
    Logger.info(log_entry, Map.to_list(metadata))
  end

  defp log_request_transport_duration(request_metadata = %{request_timestamp: request_timestamp}) do
    log_with_metadata(
      fn ->
        "Request transport duration: #{:os.system_time(:millisecond) - request_timestamp}ms"
      end,
      request_metadata
    )
  end

  defp log_request_transport_duration(_request_metadata), do: nil
end
