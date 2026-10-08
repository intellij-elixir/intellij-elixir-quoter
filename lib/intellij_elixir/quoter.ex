defmodule IntellijElixir.Quoter do
  @moduledoc """
  `Code.string_to_quoted/2` and `Code.compile_string/2` server

  Each request shape is still answered, so a client written against any of them can be upgraded on its own
  schedule:

      GenServer.call(IntellijElixir.Quoter, "1 + 2")
      #=> {:ok, {:+, [line: 1], [1, 2]}}

      GenServer.call(IntellijElixir.Quoter, {:quote, "1 + 2"})
      #=> {:ok, {:+, [line: 1], [1, 2]}, []}

      GenServer.call(IntellijElixir.Quoter, {:quote, "1 + 2", columns: true})
      #=> {:ok, {:+, [line: 1, column: 3], [1, 2]}, []}

      GenServer.call(IntellijElixir.Quoter, {:compile, "defmodule M, do: nil", timeout: 1_000})
      #=> {:ok, [], [{:start, %Macro.Env{}}, ...], []}

  `{:quote, code}` adds the diagnostics Elixir emitted while quoting that source, and `{:quote, code, opts}`
  quotes with the parser options `columns:` and `token_metadata:`. `{:compile, code, opts}` is answered by
  `IntellijElixir.Quoter.Compile`. See `capabilities/0`.
  """
  use GenServer

  alias IntellijElixir.Quoter.{Compile, Diagnostics}

  # Types

  @type t :: %{warning_capture: boolean}
  @type line :: non_neg_integer
  @type error :: any
  @type token :: binary
  @type raised :: {:raise, module | :throw | :exit, binary}
  @type quoted :: {:ok, Macro.t()} | {:error, {line, error, token}} | raised
  @type diagnosed ::
          {:ok, Macro.t(), [Diagnostics.t()]}
          | {:error, {line, error, token} | {:invalid_options, term}, [Diagnostics.t()]}
          | {:raise, module | :throw | :exit, binary, [Diagnostics.t()]}
  @type capabilities :: %{
          protocol: pos_integer,
          elixir: String.t(),
          otp: String.t(),
          mechanism: Diagnostics.mechanism(),
          warning_capture: boolean,
          compile_diagnostics: boolean
        }

  # Bump whenever a reply shape changes, so a client can tell what it is talking to. The bare binary
  # request is protocol 1; `{:quote, code}` and `:capabilities` are protocol 2; `{:quote, code, opts}` and
  # `{:compile, code, opts}` are protocol 3.
  @protocol 3

  # The parser options a client may set, each to a boolean.
  @quote_options [:columns, :token_metadata]

  # Warns on every supported release, so a boot that captures nothing proves the hook is broken
  # rather than that the source was clean.
  @self_check_source "x = ? "

  @compile_supervisor IntellijElixir.Quoter.CompileSupervisor

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
  What this build answers: its protocol, the Elixir and OTP running it, whether capturing diagnostics
  still works here, and whether compiles report diagnostics.

  `warning_capture: false` means this release's hook no longer captures. Replies stay well-formed,
  with an empty diagnostics list for every source, so a client that compares diagnostics should fail
  rather than trust them.

  `compile_diagnostics: false` means every `{:compile, code, opts}` reply has an empty diagnostics list, as on
  Elixir before 1.15.
  """
  @spec capabilities :: capabilities
  def capabilities, do: GenServer.call(__MODULE__, :capabilities)

  @doc false
  # Older releases reject some constructs by raising rather than by returning `{:error, _}`, and compiled code
  # may raise, throw or exit with anything. Answering with a term keeps the server alive, so the caller sees the
  # failure and later calls are unaffected.
  @spec answering_raises((-> result)) :: result | raised when result: var
  def answering_raises(fun) do
    fun.()
  rescue
    exception -> {:raise, exception.__struct__, Exception.message(exception)}
  catch
    :throw, thrown -> {:raise, :throw, inspect(thrown)}
    :exit, reason -> {:raise, :exit, inspect(reason)}
  end

  @doc false
  # The entries of `opts` that `valid?` rejects, or all of `opts` when it is not a keyword list, so checking what
  # a client sent never raises in the server.
  @spec invalid_options(term, (term -> boolean)) :: term
  def invalid_options(opts, valid?) do
    if Keyword.keyword?(opts), do: Enum.reject(opts, valid?), else: opts
  end

  @impl true
  @spec init([]) :: {:ok, t}
  def init(_args) do
    {:ok, %{warning_capture: warning_capture?()}}
  end

  @impl true
  @spec handle_call(
          String.t()
          | {:quote, String.t()}
          | {:quote, String.t(), keyword}
          | {:compile, String.t(), keyword}
          | :capabilities,
          GenServer.from(),
          t
        ) :: {:reply, quoted | diagnosed | Compile.t() | capabilities, t} | {:noreply, t}
  def handle_call(code, from, state) when is_binary(code) do
    answer_apart(from, state, fn ->
      {quoted, _diagnostics} = Diagnostics.capture(fn -> quote_code(code, []) end)
      quoted
    end)
  end

  def handle_call({:quote, code}, from, state) when is_binary(code) do
    answer_apart(from, state, fn -> quote_code_with_diagnostics(code, []) end)
  end

  def handle_call({:quote, code, opts}, from, state) when is_binary(code) do
    case invalid_options(opts, &valid_quote_option?/1) do
      [] -> answer_apart(from, state, fn -> quote_code_with_diagnostics(code, opts) end)
      invalid -> {:reply, {:error, {:invalid_options, invalid}, []}, state}
    end
  end

  # Answered from a process of its own, so a long compile holds up neither quoting nor other compiles.
  def handle_call({:compile, code, opts}, from, state) when is_binary(code) do
    case Compile.timeout(opts) do
      {:ok, timeout} -> answer_apart(from, state, fn -> compile(code, timeout) end)
      {:error, reply} -> {:reply, reply, state}
    end
  end

  def handle_call(:capabilities, _from, state) do
    {:reply, capabilities(state), state}
  end

  # Quotes and compiles run in processes of their own, so requests overlap. The node is prepared here, in the one
  # process that does it, because before 1.15 that registers `:standard_error` and two registrations would race.
  # `fun` raising is answered by its own rescue; a failure that still escapes leaves the caller to its call timeout.
  @spec answer_apart(GenServer.from(), t, (-> term)) :: {:noreply, t}
  defp answer_apart(from, state, fun) do
    :ok = Diagnostics.prepare_compile()

    {:ok, _child} =
      Task.Supervisor.start_child(@compile_supervisor, fn -> GenServer.reply(from, fun.()) end)

    {:noreply, state}
  end

  defp valid_quote_option?({key, value}), do: key in @quote_options and is_boolean(value)
  defp valid_quote_option?(_option), do: false

  # The caller is only answered by this process, so a failure in collecting must still reply.
  @spec compile(String.t(), pos_integer) :: Compile.t()
  defp compile(code, timeout) do
    case answering_raises(fn -> Compile.run(code, timeout) end) do
      {:raise, _kind, _message} = raised -> {raised, [], [], []}
      compiled -> compiled
    end
  end

  @spec quote_code_with_diagnostics(String.t(), keyword) :: diagnosed
  defp quote_code_with_diagnostics(code, opts) do
    {result, diagnostics} = Diagnostics.capture(fn -> quote_code(code, opts) end)

    case result do
      {:ok, quoted} -> {:ok, quoted, diagnostics}
      {:error, reason} -> {:error, reason, diagnostics}
      {:raise, kind, message} -> {:raise, kind, message, diagnostics}
    end
  end

  @spec quote_code(String.t(), keyword) :: quoted
  defp quote_code(code, opts) do
    answering_raises(fn -> Code.string_to_quoted(code, opts) end)
  end

  @spec capabilities(t) :: capabilities
  defp capabilities(%{warning_capture: warning_capture}) do
    %{
      protocol: @protocol,
      elixir: System.version(),
      otp: List.to_string(:erlang.system_info(:otp_release)),
      mechanism: Diagnostics.mechanism(),
      warning_capture: warning_capture,
      compile_diagnostics: Diagnostics.compile_capture?()
    }
  end

  @spec warning_capture? :: boolean
  defp warning_capture? do
    {_result, diagnostics} = Diagnostics.capture(fn -> quote_code(@self_check_source, []) end)

    diagnostics != []
  end
end
