# Protein for Elixir

***Multi-platform remote procedure call (RPC) system based on Protocol Buffers***

Features:

- Implement RPC services and clients for Elixir and Ruby platforms
- Call remote services using unified, simple client API
- Call to services for an immediate response or push non-blocking requests to async services
- Define services via unified, configurable DSL
- Define service input/outputs using the widely acclaimed Google Protocol Buffers format
- Transport your calls via HTTP or AMQP transports

Packages:

- [Protein for Elixir](http://github.com/surgeventures/protein-elixir)
- [Protein for Ruby](http://github.com/surgeventures/protein-ruby)

## Getting Started

Add `protein` as a dependency to your project in `mix.exs`:

```elixir
defp deps do
  [{:protein, "~> x.x.x"}]
end
```

Then run `mix deps.get` to fetch it.

## Documentation

Visit documentation on [HexDocs](https://hexdocs.pm/protein) for a complete API reference.

