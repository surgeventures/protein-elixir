defmodule Protein.EmptyServer do
  @moduledoc false

  use Protein.Server

  proto(:empty)
  proto(:error)
end

defmodule Protein.EmptyServer.EmptyService do
  @moduledoc false

  def call(_request) do
    :timer.sleep(100)
    :ok
  end
end

defmodule Protein.EmptyServer.ErrorService do
  @moduledoc false

  def call(_request) do
    raise "oops"
  end
end
