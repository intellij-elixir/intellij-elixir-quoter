defmodule IntellijElixir.Quoter.Diagnostics do
  @moduledoc """
  Captures the diagnostics `Code.string_to_quoted/1` emits, per call.

  Each release family reports them through a different hook:

    * 1.15 and later - `Code.with_diagnostics/2`, which is public.
    * 1.13 and 1.14 - the `:elixir_compiler_info` process dictionary key, which is private.
    * 1.11 and 1.12 - the `:elixir_compiler_pid` process dictionary key, which is private.

  `IntellijElixir.Quoter` proves on boot that the hook still captures, so one that stopped working
  cannot be mistaken for code that emitted no diagnostics.
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

    defp entry(%{severity: severity, position: position, message: message}) do
      {line, column} = line_and_column(position)

      {severity, line, column, IO.iodata_to_binary(message)}
    end
  else
    @key if @mechanism == :compiler_info, do: :elixir_compiler_info, else: :elixir_compiler_pid

    @doc """
    Runs `fun`, returning its result and the diagnostics it emitted, in emission order.

    Duplicates are kept: the same warning on three lines is three entries.
    """
    @spec capture((-> result)) :: {result, [t]} when result: var
    def capture(fun) when is_function(fun, 0) do
      Process.put(@key, hook())

      result =
        try do
          fun.()
        after
          Process.delete(@key)
        end

      # Each warning is sent from the process running `fun`, so all of them are in the mailbox by the
      # time it returns and the drain needs no timeout.
      {result, drain([])}
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
