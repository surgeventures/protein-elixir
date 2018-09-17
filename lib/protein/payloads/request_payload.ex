defmodule Protein.RequestPayload do
  @moduledoc false
  alias Protein.Utils

  def encode(service_name, request_buf, request_metadata) do
    Poison.encode!(%{
      "service_name" => service_name,
      "request_metadata" => request_metadata,
      "request_buf_b64" => Base.encode64(request_buf)
    })
  end

  def decode(payload) do
    decoded_payload = Poison.decode!(payload)

    service_name = Map.fetch!(decoded_payload, "service_name")

    request_buf_b64 = Map.fetch!(decoded_payload, "request_buf_b64")
    request_buf = Base.decode64!(request_buf_b64)

    request_metadata = Map.get(decoded_payload, "request_metadata", %{})
    atomic_keys_request_metadata = Utils.atomize_map_keys(request_metadata)

    {service_name, request_buf, atomic_keys_request_metadata}
  end
end
