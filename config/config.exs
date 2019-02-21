use Mix.Config

if Mix.env() == :test do
  config :logger, level: :info
  config :protein, mocking_enabled: true
  config :protein, serve: true

  config :protein, Protein.EmptyServer,
    transport: [adapter: :amqp, queue: "test", url: "amqp://test:test@localhost"]

  config :protein, Protein.EmptyClient,
    transport: [adapter: :amqp, queue: "test", url: "amqp://test:test@localhost"]
end
