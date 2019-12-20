defmodule Protein.EmptyClient do
  @moduledoc false

  use Protein.Client

  proto(:empty)
  proto(:error)
  proto(:async_error)
end
