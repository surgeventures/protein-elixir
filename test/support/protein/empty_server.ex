defmodule Protein.EmptyServer do
  @moduledoc false

  use Protein.Server

  proto(:empty)
  proto(:error)
  proto(:async_error)
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

defmodule Protein.EmptyServer.AsyncErrorService do
  @moduledoc false

  def call(_request) do
    Task.async(fn -> raise "oops" end) |> Task.await()
  end
end
