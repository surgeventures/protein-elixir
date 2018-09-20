defmodule Protein.RequestPayloadTest do
  use ExUnit.Case
  alias Protein.RequestPayload

  describe "decode/1" do
    test "decode with metadata" do
      payload =
        Poison.encode!(%{
          "service_name" => "TestService",
          "request_metadata" => %{
            timestamp: 1,
            request_id: "qwerty12345"
          },
          "request_buf_b64" => Base.encode64("Request buffer")
        })

      {service_name, request_buf, request_metadata} = RequestPayload.decode(payload)

      assert service_name == "TestService"
      assert request_buf == "Request buffer"

      assert request_metadata == %{
               timestamp: 1,
               request_id: "qwerty12345"
             }
    end

    test "decode without metadata" do
      payload =
        Poison.encode!(%{
          "service_name" => "TestService",
          "request_buf_b64" => Base.encode64("Request buffer")
        })

      {service_name, request_buf, request_metadata} = RequestPayload.decode(payload)

      assert service_name == "TestService"
      assert request_buf == "Request buffer"
      assert request_metadata == %{}
    end
  end
end
