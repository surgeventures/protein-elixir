defmodule Protein.ResponsePayloadTest do
  use ExUnit.Case, async: true
  alias Protein.ResponsePayload

  describe "encode/1" do
    test "encode success" do
      response = "asdasd"
      encoded = Base.encode64(response)
      assert ResponsePayload.encode({:ok, response, nil}) ==  ~s({"response_metadata":null,"response_buf_b64":"#{encoded}"})
    end

    test "encode error" do
      errors = [
        {:some_reason, pointer_type: :pointer_key}
      ]
      expected_encoding = ~s({"response_metadata":null,"errors":[{"reason":":some_reason",) <>
        ~s("pointer":[["pointer_type","pointer_key"]]}]})
      assert ResponsePayload.encode({:error, errors, nil}) == expected_encoding
    end
  end

  describe "decode/1" do
    test "decode with metadata" do
      payload = Poison.encode!(%{
        "response_metadata" => %{
          timestamp: 1,
          request_id: "qwerty12345"
        },
        "response_buf_b64" => Base.encode64("Response buffer")
      })

      {status, response_buf, response_metadata} = ResponsePayload.decode(payload)

      assert status == :ok
      assert response_buf == "Response buffer"
      assert response_metadata == %{
        timestamp: 1,
        request_id: "qwerty12345"
      }
    end

    test "decode without metadata" do
      payload = Poison.encode!(%{
        "response_buf_b64" => Base.encode64("Response buffer")
      })

      {status, response_buf, response_metadata} = ResponsePayload.decode(payload)

      assert status == :ok
      assert response_buf == "Response buffer"
      assert response_metadata == %{}
    end

    test "decode error with metadata" do
      payload = Poison.encode!(%{
        "errors" => [%{"reason" => "Error reason"}],
        "response_metadata" => %{
          timestamp: 1,
          request_id: "qwerty12345"
        },
      })

      {status, error_reason, response_metadata} = ResponsePayload.decode(payload)

      assert status == :error
      assert error_reason == [{"Error reason", nil}]
      assert response_metadata == %{
        timestamp: 1,
        request_id: "qwerty12345"
      }
    end

    test "decode error without metadata" do
      payload = Poison.encode!(%{
        "errors" => [%{"reason" => "Error reason"}]
      })

      {status, error_reason, response_metadata} = ResponsePayload.decode(payload)

      assert status == :error
      assert error_reason == [{"Error reason", nil}]
      assert response_metadata == %{}
    end
  end
end
