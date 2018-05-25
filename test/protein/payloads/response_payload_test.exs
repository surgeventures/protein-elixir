defmodule Protein.ResponsePayloadTest do
  use ExUnit.Case, async: true

  alias Protein.ResponsePayload

  describe "encode/1" do
    test "encode success" do
      response = "asdasd"
      encoded = Base.encode64(response)
      assert ResponsePayload.encode({:ok, response}) ==  "{\"response_buf_b64\":\"#{encoded}\"}"
    end

    test "encode error" do
      errors = [
        {:some_reason, pointer_type: :pointer_key}
      ]
      expected_encoding = "{\"errors\":[{\"reason\":\":some_reason\"," <>
        "\"pointer\":[[\"pointer_type\",\"pointer_key\"]]}]}"
      assert ResponsePayload.encode({:error, errors}) == expected_encoding
    end
  end
end
