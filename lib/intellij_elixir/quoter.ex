defmodule IntellijElixir.Quoter do
  @moduledoc """
  `Code.string_to_quoted/1` server

  Two request shapes are answered, so a client written against either can be upgraded on its own
  schedule:

      GenServer.call(IntellijElixir.Quoter, "1 + 2")
      #=> {:ok, {:+, [line: 1], [1, 2]}}

      GenServer.call(IntellijElixir.Quoter, {:quote, "1 + 2"})
      #=> {:ok, {:+, [line: 1], [1, 2]}, []}

  The second adds the diagnostics Elixir emitted while quoting that source. See `capabilities/0`.
  """
  use GenServer

  alias IntellijElixir.Quoter.Diagnostics

  # Types

  @type t :: %{warning_capture: boolean}
  @type line :: non_neg_integer
  @type error :: any
  @type token :: binary
  @type raised :: {:raise, module | :throw | :exit, binary}
  @type quoted :: {:ok, Macro.t()} | {:error, {line, error, token}} | raised
  @type diagnosed ::
          {:ok, Macro.t(), [Diagnostics.t()]}
          | {:error, {line, error, token}, [Diagnostics.t()]}
          | {:raise, module | :throw | :exit, binary, [Diagnostics.t()]}
  @type capabilities :: %{
          protocol: pos_integer,
          elixir: String.t(),
          otp: String.t(),
          mechanism: Diagnostics.mechanism(),
          warning_capture: boolean
        }

  # Bump whenever a reply shape changes, so a client can tell what it is talking to. The bare binary
  # request is protocol 1; `{:quote, code}` and `:capabilities` are protocol 2.
  @protocol 2

  # Warns on every supported release, so a boot that captures nothing proves the hook is broken
  # rather than that the source was clean.
  @self_check_source "x = ? "

  @doc """
  Starts the Quoter GenServer.

  ## Options

    * `:name` - registers the process under the given name

  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    {name, _opts} = Keyword.pop(opts, :name)
    server_opts = if name, do: [name: name], else: []
    GenServer.start_link(__MODULE__, [], server_opts)
  end

  @doc """
  What this build answers: its protocol, the Elixir and OTP running it, and whether capturing
  diagnostics still works here.

  `warning_capture: false` means this release's hook no longer captures. Replies stay well-formed,
  with an empty diagnostics list for every source, so a client that compares diagnostics should fail
  rather than trust them.
  """
  @spec capabilities :: capabilities
  def capabilities, do: GenServer.call(__MODULE__, :capabilities)

  @impl true
  @spec init([]) :: {:ok, t}
  def init(_args) do
    {:ok, %{warning_capture: warning_capture?()}}
  end

  @impl true
  @spec handle_call(String.t() | {:quote, String.t()} | :capabilities, GenServer.from(), t) ::
          {:reply, quoted | diagnosed | capabilities, t}
  def handle_call(code, _from, state) when is_binary(code) do
    {:reply, quote_code(code), state}
  end

  def handle_call({:quote, code}, _from, state) when is_binary(code) do
    {:reply, quote_code_with_diagnostics(code), state}
  end

  def handle_call(:capabilities, _from, state) do
    {:reply, capabilities(state), state}
  end

  @spec quote_code_with_diagnostics(String.t()) :: diagnosed
  defp quote_code_with_diagnostics(code) do
    {result, diagnostics} = Diagnostics.capture(fn -> quote_code(code) end)

    case result do
      {:ok, quoted} -> {:ok, quoted, diagnostics}
      {:error, reason} -> {:error, reason, diagnostics}
      {:raise, kind, message} -> {:raise, kind, message, diagnostics}
    end
  end

  # Older releases reject some constructs by raising rather than by returning `{:error, _}`. Answering
  # with a term keeps the server alive, so the caller sees the rejection and later calls are unaffected.
  @spec quote_code(String.t()) :: quoted
  defp quote_code(code) do
    Code.string_to_quoted(code)
  rescue
    exception -> {:raise, exception.__struct__, Exception.message(exception)}
  catch
    :throw, thrown -> {:raise, :throw, inspect(thrown)}
    :exit, reason -> {:raise, :exit, inspect(reason)}
  end

  @spec capabilities(t) :: capabilities
  defp capabilities(%{warning_capture: warning_capture}) do
    %{
      protocol: @protocol,
      elixir: System.version(),
      otp: List.to_string(:erlang.system_info(:otp_release)),
      mechanism: Diagnostics.mechanism(),
      warning_capture: warning_capture
    }
  end

  @spec warning_capture? :: boolean
  defp warning_capture? do
    {_result, diagnostics} = Diagnostics.capture(fn -> quote_code(@self_check_source) end)

    diagnostics != []
  end
end
