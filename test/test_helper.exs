ExUnit.configure(exclude: [external: true])
ExUnit.start()

defmodule TestUtil do
  def stop_process(pid) do
    try do
      Process.flag(:trap_exit, true)
      Process.exit(pid, :shutdown)

      receive do
        {:EXIT, _pid, _error} -> :ok
      end
    rescue
      e in RuntimeError -> e
    end

    Process.flag(:trap_exit, false)
  end
end
