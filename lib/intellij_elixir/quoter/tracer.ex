defmodule IntellijElixir.Quoter.Tracer do
  @moduledoc """
  Forwards every compiler trace event, with the environment it was traced in, to the compile it belongs to.

  Tracers are global compiler options, so this one sees every compile on the node. It routes each event as
  `IntellijElixir.Quoter.Probe.send/2` does, and drops events from any other compile.
  """

  alias IntellijElixir.Quoter.Probe

  @doc false
  # Whether the environment's module is loaded is only true now, while the compile runs, so it goes with the
  # event: the compile unloads only the modules it defined. `:erlang.module_loaded/1`, unlike
  # `:code.is_loaded/1` before OTP 26, is not a call to the code server, which is busy loading during a compile.
  @spec trace(tuple | atom, Macro.Env.t()) :: :ok
  def trace(event, %{file: file, module: module} = env) do
    case Probe.collector(file) do
      nil ->
        :ok

      collector ->
        Probe.report(
          collector,
          {:trace, event, env, module != nil and :erlang.module_loaded(module)}
        )
    end
  end

  @doc """
  Installs this tracer alongside any others already installed.
  """
  @spec install :: :ok
  def install do
    tracers = Code.get_compiler_option(:tracers)

    if __MODULE__ not in tracers do
      Code.put_compiler_option(:tracers, [__MODULE__ | tracers])
    end

    :ok
  end
end
