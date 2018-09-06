defmodule Protein.SampleClientUnresponding do
  @moduledoc false

  use Protein.Client

  transport(
    :amqp,
    url: "amqp://example.com",
    queue: "remote_rpc",
    timeout: 15_000,
    reconnect_interval: 1_000
  )

  proto(:create_user_unresponding)
end

defmodule Protein.SampleClientUnresponding.CreateUserUnrespondingMock do
  @moduledoc false

  alias Protein.SampleClientUnresponding.CreateUserUnresponding.Request

  def call(%Request{user: %Request.User{name: "Jane", gender: :FEMALE}}) do
    :ok
  end

  def call(_request) do
    raise "Sample mock failure"
  end
end
