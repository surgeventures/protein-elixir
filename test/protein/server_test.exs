defmodule Protein.ServerTest do
  use ExUnit.Case, async: true
  alias Protein.Server
  alias Protein.SampleClient.{
    CreateUser,
    CreateUserMock
  }

  describe "process/1" do
    test "process with response" do
      encoded_request = CreateUser.Request.encode(
        %CreateUser.Request{
          user: %CreateUser.Request.User{
            name: "Mary",
            gender: :FEMALE
          }
        }
      )

      service_opts = [
        service_name: "create_name",
        service_mod: CreateUserMock,
        request_mod: CreateUser.Request,
        response_mod: CreateUser.Response
      ]

      expected_response = %CreateUser.Response{
        user: %CreateUser.Response.User{
          id: 1,
          admin: false,
          name: "Mary"
        }
      }

      encoded_response = expected_response
        |> CreateUser.Response.encode()
        |> Base.encode64()

      expected_result = ~r/^{"response_metadata":{"timestamp":\d+,"request_id":null},"response_buf_b64":"#{encoded_response}"}$/

      assert Regex.match?(expected_result, Server.process(encoded_request, %{}, service_opts))
    end

    test "process without response" do
      encoded_request = CreateUser.Request.encode(
        %CreateUser.Request{
          user: %CreateUser.Request.User{
            name: "Jane",
            gender: :FEMALE
          }
        }
      )

      service_opts = [
        service_name: "create_name",
        service_mod: CreateUserMock,
        request_mod: CreateUser.Request,
        response_mod: nil
      ]

      assert is_nil(Server.process(encoded_request, %{}, service_opts))
    end
  end
end
