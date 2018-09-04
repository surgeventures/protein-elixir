defmodule Protein.ResponsePayload do
  @moduledoc false
  alias Protein.Utils

  def encode({:ok, response, response_metadata}) do
    Poison.encode!(%{
      "response_metadata" => response_metadata,
      "response_buf_b64" => Base.encode64(response)
    })
  end
  def encode({:error, errors, response_metadata}) do
    Poison.encode!(%{
      "response_metadata" => response_metadata,
      "errors" => encode_errors(errors)
    })
  end

  defp encode_errors(errors) do
    Enum.map(errors, &encode_error/1)
  end

  defp encode_error({reason, pointer}) do
    %{
      "reason" => encode_error_reason(reason),
      "pointer" => encode_error_pointer(pointer)
    }
  end

  defp encode_error_reason(atom) when is_atom(atom), do: ":#{atom}"
  defp encode_error_reason(binary) when is_binary(binary), do: binary

  defp encode_error_pointer(pointer) when is_list(pointer) do
    Enum.map(pointer, &encode_error_pointer_item/1)
  end
  defp encode_error_pointer(_), do: nil

  defp encode_error_pointer_item({type, key}), do: [to_string(type), key]

  def decode(payload) do
    case Poison.decode!(payload) do
      %{"errors" => errors, "response_metadata" => response_metadata} when is_list(errors) ->
        {:error, decode_errors(errors), Utils.atomize_map_keys(response_metadata)}
      %{"errors" => errors} when is_list(errors) ->
        {:error, decode_errors(errors), %{}}
      %{"response_buf_b64" => response_buf_b64, "response_metadata" => response_metadata} ->
        {:ok, Base.decode64!(response_buf_b64), Utils.atomize_map_keys(response_metadata)}
      %{"response_buf_b64" => response_buf_b64} ->
        {:ok, Base.decode64!(response_buf_b64), %{}}
    end
  end

  defp decode_errors(errors) do
    Enum.map(errors, fn error ->
      {
        decode_error_reason(error),
        decode_error_pointer(error)
      }
    end)
  end

  defp decode_error_reason(%{"reason" => ":" <> reason}), do: String.to_atom(reason)
  defp decode_error_reason(%{"reason" => reason}), do: reason

  defp decode_error_pointer(%{"pointer" => pointer}) when is_list(pointer) do
    Enum.map(pointer, &decode_error_pointer_item/1)
  end
  defp decode_error_pointer(_), do: nil

  defp decode_error_pointer_item(["struct", key]), do: {:struct, key}
  defp decode_error_pointer_item(["map", key]), do: {:map, key}
  defp decode_error_pointer_item(["repeated", key]), do: {:repeated, key}
end
