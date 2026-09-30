defmodule IntellijElixir.Quoter.Probe do
  @moduledoc """
  How code compiled by a `{:compile, code, opts}` request reports back to it.

  Each compile runs under a file name of its own, so the environment of any code it compiles says which compile
  to report to. A probe passes that environment, `__CALLER__` in a macro or `__ENV__` elsewhere, with the term
  to report:

      defmacro probe(term) do
        IntellijElixir.Quoter.Probe.send(__CALLER__, term)
        :ok
      end

  The term becomes one of the compile's messages, in the order it arrived. An environment that belongs to no
  running compile, such as one whose file was changed with `@file`, reports nowhere.
  """

  import Kernel, except: [send: 2]

  @registry IntellijElixir.Quoter.Compiles

  @doc """
  Reports `message` to the compile that `env` belongs to, if it is still running.
  """
  @spec send(Macro.Env.t(), term) :: :ok
  def send(%{file: file}, message), do: report(collector(file), {:probe, message})

  @doc false
  # Makes the calling process the collector for everything compiled under `file`.
  @spec collect(String.t()) :: :ok
  def collect(file) do
    {:ok, _owner} = Registry.register(@registry, file, nil)

    :ok
  end

  @doc false
  # Anything reported under `file` after this reports nowhere.
  @spec stop_collecting(String.t()) :: :ok
  def stop_collecting(file), do: Registry.unregister(@registry, file)

  @doc false
  # The collector for everything compiled under `file`, or `nil` when no compile runs under it. Shared with
  # `IntellijElixir.Quoter.Tracer`, which routes the same way.
  @spec collector(String.t()) :: pid | nil
  def collector(file) do
    case Registry.lookup(@registry, file) do
      [{collector, _value}] -> collector
      [] -> nil
    end
  end

  @doc false
  # Tagged, so the collector receives every report, probe or trace, with one pattern.
  @spec report(pid | nil, term) :: :ok
  def report(nil, _report), do: :ok

  def report(collector, report) do
    Kernel.send(collector, {__MODULE__, report})

    :ok
  end
end
