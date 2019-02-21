defmodule Protein.EmptyServer do
  @moduledoc false

  use Protein.Server

  proto(:empty)
end

defmodule Protein.EmptyServer.EmptyService do
  def call(_request) do
    :timer.sleep(100)
    :ok
  end
end
