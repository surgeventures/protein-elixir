defmodule Protein.Client do
  @moduledoc """
  Calls services in remote systems.

  ## Usage

  Here's how your RPC client module may look like:

      defmodule MyProject.RemoteRPC do
        use Protein.Client

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
                mock_mod: __MODULE__.CreateUserMock
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
            supervisor(MyProject.RemoteRPC, []),
          ]

          opts = [strategy: :one_for_one, name: MyProject.Supervisor]
          Supervisor.start_link(children, opts)
        end
      end

  Having that, you can call your RPC as follows:

      alias MyProject.RemoteRPC
      alias MyProject.RemoteRPC.CreateUser.{Request, Response}

      request = %Request{}

      case RemoteRPC.call(request) do
        {:ok, response = %Response{}} ->
          # do stuff with response
        {:error, errors}
          # do stuff with errors
      end

      # ...or assume that a failure is out of the question
      response = RemoteRPC.call!(request)

      # ...or issue a push to non-responding service (recognized by lack of Response structure)
      RemoteRPC.push(request)

  ### Macros and functions

  By invoking `use Protein.Client`, you include the following in your client module:

  - `Protein.RouterAPI`: macros for defining a list of services and transport options
  - `Protein.ClientAPI`: functions for making client requests to remote services

  ### Mocking for tests

  Client call mocking is enabled by default for `Mix.env == :test`. You can configure it explicitly
  via the `mocking_enabled` config flag as follows:

      config :protein, mocking_enabled: true

  You can add a mock module for your specific service to `test/support`. The module should be the
  `mock_mod` on sample above (which by default is a `service_mod` with the `Mock` suffix). For
  example, to mock the service sourced from `create_user.proto` on example above, you may implement
  the following module:

      # test/support/my_project/remote_rpc/create_user_mock.ex

      alias MyProject.RemoteRPC.CreateUser.{Request, Response}

      defmodule MyProject.RemoteRPC.CreateUserMock do
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

  You can define multiple `call` clauses in your mock and use pattern matching to create different
  output based on varying input.

  Mock bypasses the transport layer (obviously), but it still encodes/decodes your request protobuf
  just as regular client does and it still encodes/decodes the response from your mock. This ensures
  that your test structures are compilant with specific proto in use.

  For non-responding services, mock modules are optional and will be executed only if defined.
  Otherwise, the client with mocking mode enabled will still encode the request, but then it will
  silently drop it without throwing an error.

  """

  alias Protein.{
    CallError,
    DummyServiceMock,
    RequestPayload,
    ResponsePayload,
    Server,
    Transport,
    TransportError,
    Utils
  }

  defmacro __using__(_) do
    quote do
      use Protein.{RouterAPI, ClientAPI}
      use Supervisor
      alias Protein.{Transport, Utils}

      def start_link(_opts \\ []) do
        Supervisor.start_link(__MODULE__, [], name: __MODULE__)
      end

      def init(_) do
        Supervisor.init([], strategy: :one_for_one)
      end
    end
  end

  @doc false
  def call(request_struct, service_opts, transport_opts) do
    service_name = Keyword.fetch!(service_opts, :service_name)
    request_mod = Keyword.fetch!(service_opts, :request_mod)
    response_mod = Keyword.fetch!(service_opts, :response_mod)
    mock_mod = Keyword.fetch!(service_opts, :mock_mod)

    unless Code.ensure_loaded?(response_mod), do: raise("Called to non-responding service")

    request_buf = request_mod.encode(request_struct)

    result =
      call_via_mock(request_buf, request_mod, response_mod, mock_mod) ||
        call_via_adapter(service_name, request_buf, transport_opts)

    case result do
      {:ok, response_buf} ->
        {:ok, response_mod.decode(response_buf)}

      {:error, errors} ->
        {:error, errors}
    end
  end

  @doc false
  def call!(request_struct, service_opts, transport_opts) do
    request_struct
    |> call(service_opts, transport_opts)
    |> handle_non_failing_response()
  end

  defp call_via_mock(request_buf, request_mod, response_mod, mock_mod) do
    if Utils.mocking_enabled?() do
      Server.process_service(mock_mod, request_buf, request_mod, response_mod)
    end
  rescue
    error -> raise TransportError, adapter: :mock, context: error
  end

  defp call_via_adapter(service_name, request_buf, opts) do
    {adapter, adapter_opts} = Keyword.pop(opts, :adapter)
    request_payload = RequestPayload.encode(service_name, request_buf)

    response_payload =
      adapter
      |> Utils.resolve_adapter()
      |> apply(:call, [request_payload, adapter_opts])

    ResponsePayload.decode(response_payload)
  end

  defp handle_non_failing_response({:ok, response}), do: response

  defp handle_non_failing_response({:error, errors}) do
    raise CallError, errors: errors
  end

  @doc false
  def push(request_struct, service_opts, transport_opts) do
    service_name = Keyword.fetch!(service_opts, :service_name)
    request_mod = Keyword.fetch!(service_opts, :request_mod)
    response_mod = Keyword.fetch!(service_opts, :response_mod)
    mock_mod = Keyword.fetch!(service_opts, :mock_mod)

    if Code.ensure_loaded?(response_mod), do: raise("Pushed to responding service")

    request_buf = request_mod.encode(request_struct)

    push_via_mock(request_buf, request_mod, mock_mod) ||
      push_via_adapter(service_name, request_buf, transport_opts)

    :ok
  end

  defp push_via_mock(request_buf, request_mod, mock_mod) do
    if Utils.mocking_enabled?() do
      mock_or_default_mod =
        if Code.ensure_loaded?(mock_mod) do
          mock_mod
        else
          DummyServiceMock
        end

      Server.process_service(mock_or_default_mod, request_buf, request_mod)
    end
  rescue
    error -> raise TransportError, adapter: :mock, context: error
  end

  defp push_via_adapter(service_name, request_buf, opts) do
    {adapter, adapter_opts} = Keyword.pop(opts, :adapter)
    request_payload = RequestPayload.encode(service_name, request_buf)

    adapter
    |> Utils.resolve_adapter()
    |> apply(:push, [request_payload, adapter_opts])
  end
end
