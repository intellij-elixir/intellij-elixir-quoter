defmodule IntellijElixir.Quoter.Compile do
  @moduledoc """
  Answers `{:compile, code, opts}`.

  `code` is compiled by `Code.compile_string/2` in a process of its own, under a file name no other compile uses.
  The process that started it collects what the compile's probes report (see `IntellijElixir.Quoter.Probe`) and
  every event `IntellijElixir.Quoter.Tracer` traces, so compiles running at once never see each other's. Every
  module the compile introduced is unloaded before the reply. A module that was already loaded when the compile
  first traced it is left alone, even if the compile replaced it. The caller must not compile code that defines a
  module already loaded, or one a compile running at once defines, and no compiled code may change the node's
  compiler tracers.

  The reply is always `{status, messages, events, diagnostics}`, so what arrived before a failure is kept:

    * `status` is `:ok`, `{:error, reason}` for options it does not take, `{:raise, kind, message}` when the
      compile raises, throws or exits, or `:timeout` when it outlives its timeout and is killed;
    * `messages` are the terms the probes reported, and `events` the `{event, env}` pairs the tracer saw, each
      in arrival order;
    * `diagnostics` are captured on Elixir 1.15 and later, and always empty before it, where capturing them
      would change how the code compiles. They are empty on a timeout too.

  What the compile prints is discarded before 1.15 (see `IntellijElixir.Quoter.Discard`), so a console that has
  stopped draining cannot hold it up until its timeout.
  """

  alias IntellijElixir.Quoter
  alias IntellijElixir.Quoter.{Diagnostics, Probe, Tracer}

  @type status :: :ok | {:error, {:invalid_options, term}} | Quoter.raised() | :timeout
  @type event :: {tuple | atom, Macro.Env.t()}
  @type t :: {status, messages :: [term], [event], [Diagnostics.t()]}

  @default_timeout 5_000

  # The longest `Process.send_after/3` accepts.
  @max_timeout 4_294_967_295

  @doc """
  The timeout, in milliseconds, that `opts` give a compile, or the reply to options it does not take.
  """
  @spec timeout(term) :: {:ok, pos_integer} | {:error, t}
  def timeout(opts) do
    case Quoter.invalid_options(opts, &valid_option?/1) do
      [] -> {:ok, Keyword.get(opts, :timeout, @default_timeout)}
      invalid -> {:error, {{:error, {:invalid_options, invalid}}, [], [], []}}
    end
  end

  @doc """
  Compiles `code`, killing the compile after `timeout` milliseconds.
  """
  @spec run(String.t(), pos_integer) :: t
  def run(code, timeout) do
    file = "quoter-compile-#{System.unique_integer([:positive])}.ex"
    # Every compile, rather than once, because compiled code can reset the node's tracers.
    :ok = Tracer.install()
    :ok = Probe.collect(file)

    collector = self()
    ref = make_ref()
    {worker, monitor} = spawn_monitor(fn -> send(collector, {ref, compile(code, file)}) end)

    try do
      # Left to fire into this process's mailbox if the compile finishes first: the process ends with the reply.
      Process.send_after(self(), {ref, :timeout}, timeout)

      {status, diagnostics, collected} = await(ref, worker, monitor, {[], [], %{}})
      :ok = Probe.stop_collecting(file)
      {messages, events, owned} = drain(collected)

      unload(owned)

      {status, Enum.reverse(messages), Enum.reverse(events), diagnostics}
    after
      # Not linked, so a failure here would otherwise leave it compiling with no time limit.
      Process.exit(worker, :kill)
    end
  end

  defp valid_option?({:timeout, timeout}) when timeout in 1..@max_timeout, do: true
  defp valid_option?(_option), do: false

  @spec compile(String.t(), String.t()) :: {:ok | Quoter.raised(), [Diagnostics.t()]}
  defp compile(code, file) do
    Diagnostics.capture_compile(fn ->
      Quoter.answering_raises(fn ->
        _modules = Code.compile_string(code, file)
        :ok
      end)
    end)
  end

  # Messages from the worker arrive in the order it sent them, and its result after all of them.
  defp await(ref, worker, monitor, collected) do
    receive do
      {Probe, report} ->
        await(ref, worker, monitor, collect(report, collected))

      {^ref, :timeout} ->
        Process.exit(worker, :kill)
        await_down(monitor)
        {:timeout, [], collected}

      {^ref, {status, diagnostics}} ->
        await_down(monitor)
        {status, diagnostics, collected}

      {:DOWN, ^monitor, :process, _worker, reason} ->
        {{:raise, :exit, inspect(reason)}, [], collected}
    end
  end

  # Unloading must wait until nothing runs the compiled code, and killing is asynchronous.
  defp await_down(monitor) do
    receive do
      {:DOWN, ^monitor, :process, _worker, _reason} -> :ok
    end
  end

  # Processes the compiled code spawned may have reported after the worker ended.
  defp drain(collected) do
    receive do
      {Probe, report} -> drain(collect(report, collected))
    after
      0 -> collected
    end
  end

  # Newest first, and which of the modules seen are this compile's to unload.
  defp collect({:probe, message}, {messages, events, owned}) do
    {[message | messages], events, owned}
  end

  defp collect({:trace, event, env, loaded}, {messages, events, owned}) do
    {messages, [{event, env} | events], own(owned, event, env.module, loaded)}
  end

  # Every module the compile defined is the module of some traced environment, and was not loaded when the
  # compile first traced it. No one event names them all on every release: 1.11 and 1.12 trace
  # `{:defmodule, meta}` and no `:on_module`; 1.13 to 1.16.1 trace only `:on_module`, after the module is
  # loaded, and after `@after_compile`, so it is missed when that raises; from 1.16.2 `:defmodule` is an atom.
  # A module whose first trace is its `:on_module` is this compile's, because only the compile that defined it
  # traces that: on 1.13 to 1.16.1 a module whose body traces nothing is first traced loaded.
  defp own(owned, _event, nil, _loaded), do: owned

  defp own(owned, event, module, loaded) do
    Map.put_new(owned, module, not loaded or match?({:on_module, _bytecode, _ignore}, event))
  end

  defp unload(owned) do
    for {module, true} <- owned do
      :code.purge(module)
      :code.delete(module)
      :code.purge(module)
    end

    :ok
  end
end
