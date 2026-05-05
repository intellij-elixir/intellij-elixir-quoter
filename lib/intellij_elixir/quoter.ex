defmodule IntellijElixir.Quoter do
  @moduledoc """
  `Code.string_to_quoted/1` server
  """
  use GenServer

  # Types

  @type t :: []
  @type line :: non_neg_integer
  @type error :: any
  @type token :: binary

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

  @impl true
  def init(state) do
    {:ok, state}
  end

  @impl true
  @spec handle_call(String.t(), GenServer.from(), t) ::
          {:reply, {:ok, Macro.t()} | {:error, {line, error, token}}, t}
  def handle_call(code, _from, state) do
    {:reply, Code.string_to_quoted(code), state}
  end
end
