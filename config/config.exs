use Mix.Config

if Mix.env == :test do
  config :logger, level: :info
  config :protein, mocking_enabled: true
end
