defmodule IntellijElixir.Quoter.Diagnostics do
  @moduledoc """
  Captures the diagnostics `Code.string_to_quoted/2`, and from 1.15 `Code.compile_string/2`, emit, per call.

  Each release family reports them through a different hook:

    * 1.15 and later - `Code.with_diagnostics/2`, which is public.
    * 1.13 and 1.14 - the `:elixir_compiler_info` process dictionary key, which is private.
    * 1.11 and 1.12 - the `:elixir_compiler_pid` process dictionary key, which is private.

  `IntellijElixir.Quoter` proves on boot that the hook still captures, so one that stopped working
  cannot be mistaken for code that emitted no diagnostics.

  Before 1.15 Elixir also prints every warning it reports, and what it prints is dropped (see
  `IntellijElixir.Quoter.Discard`), so a console that has stopped draining cannot hold the quoter. From 1.15 nothing is
  printed while capturing.
  """

  @typedoc "Before 1.15 only warnings are reachable."
  @type severity :: :warning | :error

  @typedoc "`nil` on 1.11 and 1.12, which report no column."
  @type column :: pos_integer | nil

  @type t :: {severity, line :: pos_integer | nil, column, message :: binary}

  @type mechanism :: :with_diagnostics | :compiler_info | :compiler_pid

  # intellij-elixir builds the quoter with the same Elixir that runs it, so the release is known
  # here and only the matching `capture/1` is ever defined.
  @mechanism (cond do
                Version.match?(System.version(), ">= 1.15.0") -> :with_diagnostics
                Version.match?(System.version(), ">= 1.13.0") -> :compiler_info
                true -> :compiler_pid
              end)

  @doc """
  Which hook `capture/1` uses.
  """
  @spec mechanism :: mechanism
  def mechanism, do: @mechanism

  @doc """
  Whether `capture_compile/1` captures anything on this release.
  """
  @spec compile_capture? :: boolean
  def compile_capture?, do: @mechanism == :with_diagnostics

  if @mechanism == :with_diagnostics do
    @doc """
    Runs `fun`, returning its result and the diagnostics it emitted, in emission order.

    Duplicates are kept: the same warning on three lines is three entries.
    """
    @spec capture((-> result)) :: {result, [t]} when result: var
    def capture(fun) when is_function(fun, 0) do
      # A release without `Code.with_diagnostics/2` never evaluates this `def`, so its body is never
      # compiled and cannot warn as undefined there.
      {result, diagnostics} = Code.with_diagnostics(fun)

      {result, Enum.map(diagnostics, &entry/1)}
    end

    @doc """
    Runs `fun`, a compile, returning its result and the diagnostics it emitted, in emission order.

    Unlike quoting, compiling also reports what the checker finds after the modules are defined.
    """
    @spec capture_compile((-> result)) :: {result, [t]} when result: var
    def capture_compile(fun), do: capture(fun)

    @doc """
    Gets the node ready for a compile, in the process that starts it. Nothing is needed from 1.15.
    """
    @spec prepare_compile :: :ok
    def prepare_compile, do: :ok

    defp entry(%{severity: severity, position: position, message: message}) do
      {line, column} = line_and_column(position)

      {severity, line, column, IO.iodata_to_binary(message)}
    end
  else
    alias IntellijElixir.Quoter.Discard

    @key if @mechanism == :compiler_info, do: :elixir_compiler_info, else: :elixir_compiler_pid

    @doc """
    Runs `fun`, returning its result and the diagnostics it emitted, in emission order.

    Duplicates are kept: the same warning on three lines is three entries. What Elixir prints for them is dropped.
    """
    @spec capture((-> result)) :: {result, [t]} when result: var
    def capture(fun) when is_function(fun, 0) do
      Discard.ensure()
      Process.put(@key, hook())

      result =
        try do
          Discard.as_member(fun)
        after
          Process.delete(@key)
        end

      # Each warning is sent from the process running `fun`, so all of them are in the mailbox by the
      # time it returns and the drain needs no timeout.
      {result, drain([])}
    end

    @doc """
    Runs `fun`, a compile, returning its result and no diagnostics, and drops what the compile prints.

    This release's hook is the parallel compiler's own protocol. Setting it for a compile makes every module wait
    for the compiler to acknowledge it, makes missing modules wait for the compiler to find them, and, from 1.13,
    skips the checker, so the code would not compile as it does outside the quoter. So the warnings are neither
    captured nor printed: the calling process becomes a member of the discarding server for the rest of its life, as
    does everything the compile spawns, and `prepare_compile/0` must have run first.
    """
    @spec capture_compile((-> result)) :: {result, [t]} when result: var
    def capture_compile(fun) when is_function(fun, 0) do
      Discard.join()
      {fun.(), []}
    end

    @doc """
    Gets the node ready for a compile, in the process that starts it: `:standard_error` is the discarding server
    before the compile's process starts, so that process only ever joins it.
    """
    @spec prepare_compile :: :ok
    def prepare_compile do
      Discard.ensure()
      :ok
    end

    if @mechanism == :compiler_info do
      defp hook, do: {self(), make_ref()}
    else
      defp hook, do: self()
    end

    # Selective on the warning shape, so a `$gen_call` already queued behind this one stays queued.
    defp drain(acc) do
      receive do
        {:warning, _file, position, message} ->
          {line, column} = line_and_column(position)

          drain([{:warning, line, column, IO.iodata_to_binary(message)} | acc])
      after
        0 -> Enum.reverse(acc)
      end
    end
  end

  defp line_and_column(position) do
    case position do
      {line, column} -> {line, column}
      line when is_integer(line) -> {line, nil}
      _ -> {nil, nil}
    end
  end
end
