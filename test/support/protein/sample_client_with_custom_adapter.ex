defmodule Protein.SampleClientWithCustomAdapter.Adapter do
  @moduledoc false

  def call(_, opts) do
    raise("Dummy adapter (opts: #{inspect(opts)})")
  end
end

defmodule Protein.SampleClientWithCustomAdapter do
  @moduledoc false

  use Protein.Client

  transport(__MODULE__.Adapter, x: "y")

  proto(:empty)

  service(
    proto: [from: Path.expand("./proto/empty.proto", __DIR__)],
    service_name: "create_user",
    proto_mod: __MODULE__.EmptyService,
    request_mod: __MODULE__.EmptyService.Request,
    response_mod: __MODULE__.EmptyService.Response,
    mock_mod: __MODULE__.EmptyService.Mock
  )
end
