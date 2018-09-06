defmodule Protein.SampleClientWithoutService do
  @moduledoc false

  use Protein.Client

  transport(__MODULE__.Adapter, x: "y")
end
