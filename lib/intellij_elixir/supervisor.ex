defmodule IntellijElixir.Supervisor do
  @moduledoc """
  Supervises `IntellijElixir.Quoter` and the compiles it starts
  """

  use Supervisor

  @spec start_link :: Supervisor.on_start()
  def start_link do
    Supervisor.start_link(__MODULE__, :ok)
  end

  @quoter_module IntellijElixir.Quoter

  @impl true
  def init(:ok) do
    # The quoter starts compiles under the task supervisor, and each compile collects through the registry.
    children = [
      {Registry, keys: :unique, name: IntellijElixir.Quoter.Compiles},
      {Task.Supervisor, name: IntellijElixir.Quoter.CompileSupervisor},
      {IntellijElixir.Quoter, name: @quoter_module}
    ]

    # Tuned based on intellij-elixir processing 1019 tests in 4 seconds, which is 254.75 tests per second.  Although
    # most tests are not expected to cause exits, just tuning to the test rate is less coupled than tuning to the
    # expected exit rate as expected exit is a new assertion for testing.
    Supervisor.init(children, strategy: :one_for_one, max_restarts: 1000, max_seconds: 4)
  end
end
