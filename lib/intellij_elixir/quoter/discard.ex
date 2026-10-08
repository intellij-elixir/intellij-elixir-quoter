defmodule IntellijElixir.Quoter.Discard do
  @moduledoc false

  # Before 1.15 Elixir prints every warning with a synchronous write to the process registered as `:standard_error`,
  # and there is no hook that stops the print without changing how the code compiles. Under `run_erl` that process
  # writes to a pty, and when the pty stops draining the writer is suspended: a compile until its timeout, and a
  # quote, which runs in the `IntellijElixir.Quoter` process itself, for as long as the pty stays stopped, with every
  # later request behind it.
  #
  # So the quoter takes the name `:standard_error` for a server of its own. A request from one of its members, a
  # local process whose group leader is the server, is answered at once and dropped. Any other request goes on
  # unchanged to the latest device the server displaced that is still alive, so a write that is not the quoter's
  # reaches the console, or whatever a test registered, as it did before.
  #
  # Compiles join the server for the life of their worker, and so does everything the compile spawns, because a
  # process inherits its parent's group leader. Quoting joins only while it quotes.

  @key {__MODULE__, :server}

  @doc """
  Makes sure `:standard_error` names the server, starting it the first time.

  A name another process has taken since (a test, `ExUnit.CaptureIO`) is displaced into the same server's devices and
  taken back, so nothing is wrapped twice, no second server starts, and a compile already running keeps its group
  leader. Only the `IntellijElixir.Quoter` process calls this, so two registrations never race.
  """
  @spec ensure :: pid
  def ensure do
    server = server()

    case Process.whereis(:standard_error) do
      ^server ->
        server

      displaced ->
        ref = make_ref()
        send(server, {:displaced, displaced, self(), ref})

        receive do
          {^ref, :ok} -> :ok
        end

        if displaced, do: Process.unregister(:standard_error)
        Process.register(server, :standard_error)
        server
    end
  end

  @doc """
  Makes the calling process a member for the rest of its life.
  """
  @spec join :: true
  def join, do: Process.group_leader(self(), :persistent_term.get(@key))

  @doc """
  Runs `fun` as a member, then restores the calling process's group leader.
  """
  @spec as_member((-> result)) :: result when result: var
  def as_member(fun) do
    leader = Process.group_leader()
    join()

    try do
      fun.()
    after
      Process.group_leader(self(), leader)
    end
  end

  defp server do
    case :persistent_term.get(@key, nil) do
      pid when is_pid(pid) -> if Process.alive?(pid), do: pid, else: start()
      nil -> start()
    end
  end

  defp start do
    server = spawn(fn -> loop([]) end)
    :persistent_term.put(@key, server)
    server
  end

  # `devices` are the processes displaced, latest first, each monitored: one that registers `:standard_error` and later
  # exits must not leave a write that is not the quoter's with nowhere to go.
  defp loop(devices) do
    receive do
      {:displaced, nil, from, ref} ->
        send(from, {ref, :ok})
        loop(devices)

      {:displaced, device, from, ref} ->
        devices =
          if device in devices do
            [device | List.delete(devices, device)]
          else
            Process.monitor(device)
            [device | devices]
          end

        send(from, {ref, :ok})
        loop(devices)

      {:DOWN, _ref, :process, device, _reason} ->
        loop(List.delete(devices, device))

      {:io_request, from, reply_as, request} = message ->
        cond do
          member?(from) -> send(from, {:io_reply, reply_as, reply(request)})
          devices != [] -> send(hd(devices), message)
          true -> send(from, {:io_reply, reply_as, {:error, :terminated}})
        end

        loop(devices)

      _other ->
        loop(devices)
    end
  end

  # `Process.info/2` raises for a process on another node, and answers `nil` for one that has exited.
  defp member?(pid) when node(pid) == node(),
    do: Process.info(pid, :group_leader) == {:group_leader, self()}

  defp member?(_pid), do: false

  # What `:standard_error` answers a write, and nothing else: a member that asks for anything more gets an error
  # rather than a hang.
  defp reply({:put_chars, _encoding, _chars}), do: :ok
  defp reply({:put_chars, _encoding, _module, _function, _args}), do: :ok

  defp reply({:requests, requests}),
    do: Enum.reduce(requests, :ok, fn request, _reply -> reply(request) end)

  defp reply(_request), do: {:error, :request}
end
