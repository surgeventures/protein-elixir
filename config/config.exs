use Mix.Config

if Mix.env == :test do
  config :logger, level: :warn
  config :protein, mocking_enabled: true
end
