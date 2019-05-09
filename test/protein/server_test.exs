defmodule Protein.ServerTest do
  use ExUnit.Case, async: false
  @moduletag :external

  alias Mix.Config

  alias Protein.{
    EmptyClient,
    EmptyServer
  }

  import TestUtil

  describe "start_link/1" do
    test "graceful shutdown success" do
      Config.persist(
        protein: [
          mocking_enabled: false
        ]
      )

      {:ok, server_pid} = EmptyServer.start_link()
      {:ok, _client_pid} = EmptyClient.start_link()

      request = %EmptyClient.Empty.Request{}

      parent = self()

      spawn(fn ->
        Process.flag(:trap_exit, true)
        response = EmptyClient.call(request)
        send(parent, response)
      end)

      # wait for server to start processing
      :timer.sleep(50)

      try do
        Process.flag(:trap_exit, true)
        Process.exit(server_pid, :shutdown)

        receive do
          {:EXIT, _pid, _error} -> :ok
        end
      rescue
        e in RuntimeError -> e
      end

      Process.flag(:trap_exit, false)

      receive do
        response ->
          assert {:ok, %Protein.EmptyClient.Empty.Response{}} == response
      end
    after
      Config.persist(
        protein: [
          mocking_enabled: true
        ]
      )
    end

    test "success" do
      Config.persist(
        protein: [
          mocking_enabled: false
        ]
      )

      {:ok, server_pid} = EmptyServer.start_link()
      {:ok, client_pid} = EmptyClient.start_link()

      request = %EmptyClient.Empty.Request{}
      _response = EmptyClient.call(request)

      :timer.sleep(50)

      stop_process(server_pid)
      stop_process(client_pid)
    after
      Config.persist(
        protein: [
          mocking_enabled: true
        ]
      )
    end

    test "failed" do
      Config.persist(
        protein: [
          mocking_enabled: false
        ]
      )

      {:ok, server_pid} = EmptyServer.start_link()

      _result =
        try do
          {:ok, client_pid} = EmptyClient.start_link()

          request = %EmptyClient.Error.Request{}
          _response = EmptyClient.call(request)

          :timer.sleep(50)

          stop_process(server_pid)
          stop_process(client_pid)
        rescue
          e ->
            assert %Protein.TransportError{adapter: Protein.AMQPAdapter, context: :service_error} ==
                     e
        end
    after
      Config.persist(
        protein: [
          mocking_enabled: true
        ]
      )
    end
  end
end
