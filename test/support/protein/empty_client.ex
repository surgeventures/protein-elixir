defmodule Protein.EmptyClient do
  @moduledoc false

  use Protein.Client

  proto(:empty)
  proto(:error)
end
