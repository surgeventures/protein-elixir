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

  By invoking `use Protein.Client`, you include the `Protein.Router` macros in your client as
  a means for defining a list of services and transport options. Check out its documentation for
  more information.

  Under normal circumstances, the server is invoked by traffic from the transport layer and not
  directly. Still, you can make it process a request by bypassing the transport and invoking the
  `process/1` function directly. It takes the request payload (that would normally come via
  transport layer) as argument and returns response payload (that would normally get returned via
  transport layer) or nil (for non-responding services).

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
  alias Protein.{RequestPayload, ResponsePayload, Utils}

  defmacro __using__(_) do
    quote do
      use Protein.Router
      use Supervisor
      require Logger
      alias Protein.{Server, Transport}

      def start_link(_opts \\ []) do
        Supervisor.start_link(__MODULE__, [], name: __MODULE__)
      end

      def init(_) do
        transport_opts = __transport_opts__()
        transport_server_mod =
          transport_opts
          |> Keyword.fetch!(:adapter)
          |> Utils.resolve_adapter()
          |> Utils.resolve_adapter_server_mod()
        transport_server_opts = Keyword.put(transport_opts, :server_mod, __MODULE__)

        Supervisor.init([
          {transport_server_mod, transport_server_opts}
        ], strategy: :one_for_one)
      end

      def process(request) do
        {service_name, request_buf} = RequestPayload.decode(request)
        service_opts = __service_opts__(service_name)

        Server.process(request_buf, service_opts)
      end
    end
  end

  @doc false
  def process(request_buf, service_opts) do
    service_name = Keyword.fetch!(service_opts, :service_name)
    service_mod = Keyword.fetch!(service_opts, :service_mod)
    request_mod = Keyword.fetch!(service_opts, :request_mod)
    response_mod = Keyword.fetch!(service_opts, :response_mod)
    request_type = detect_request_type(response_mod)

    case request_type do
      :call ->
        response = log_process(request_type, service_name, fn ->
          process_service(service_mod, request_buf, request_mod, response_mod)
        end)
        ResponsePayload.encode(response)
      :push ->
        log_process(:push, service_name, fn ->
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
  def process_service(service_mod, request_buf, request_mod, response_mod) do
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
  end

  defp normalize_error(reason) when is_atom(reason) or is_binary(reason), do: {reason, nil}
  defp normalize_error({reason, pointer}), do: {reason, pointer}

  defp detect_request_type(response_mod) do
    case Code.ensure_loaded(response_mod) do
      {:module, _} -> :call
      _ -> :push
    end
  end

  defp log_process(kind, service_name, process_func) do
    Logger.info(fn -> "Processing RPC #{kind}: #{service_name}" end)

    start_time = :os.system_time(:millisecond)
    result = process_func.()
    duration_ms = :os.system_time(:millisecond) - start_time
    status_text = case {kind, result} do
      {:push, _} -> "Processed"
      {:call, {:ok, _}} -> "Resolved"
      {:call, _} -> "Rejected"
    end

    Logger.info(fn -> "#{status_text} in #{duration_ms}ms" end)

    result
  end
end
