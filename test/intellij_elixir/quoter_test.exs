defmodule IntellijElixir.QuoterTest.Preexisting do
  @moduledoc false
  def here?, do: true
end

defmodule IntellijElixir.QuoterTest do
  use ExUnit.Case

  alias IntellijElixir.QuoterTest.Preexisting

  @code "Alias.function positional, key: value"
  @quoted Code.string_to_quoted(@code)

  # Raises on every supported release, unlike the constructs whose rejection moved from a raise to an
  # error tuple across versions.
  @raising <<0xFF>>

  # The one warning whose wording is byte-identical on every supported release, so it can be asserted
  # exactly.
  @warning_source "x = ? "
  @warning_message "found ? followed by code point 0x20 (space), please use ?\\s instead"

  # 1.11 and 1.12 report no column.
  @warning_column if Version.match?(System.version(), ">= 1.13.0"), do: 5, else: nil

  # Before 1.15 a compile's warnings cannot be captured without changing how it compiles.
  @compile_diagnostics Version.match?(System.version(), ">= 1.15.0")

  describe "the bare binary request" do
    test "responds to GenServer.call" do
      assert @quoted == GenServer.call(IntellijElixir.Quoter, @code)
    end

    test "responds to raw send of GenServer.call" do
      ref = make_ref()
      send(IntellijElixir.Quoter, {:"$gen_call", {self(), ref}, @code})

      assert_receive {^ref, @quoted}
    end

    test "answers a raise with a term" do
      assert {:raise, UnicodeConversionError, message} =
               GenServer.call(IntellijElixir.Quoter, @raising)

      assert is_binary(message)
    end

    test "survives a raise" do
      pid = Process.whereis(IntellijElixir.Quoter)
      GenServer.call(IntellijElixir.Quoter, @raising)

      assert Process.whereis(IntellijElixir.Quoter) == pid
      assert @quoted == GenServer.call(IntellijElixir.Quoter, @code)
    end

    test "keeps its reply shape now that {:quote, code} exists" do
      # A client written against protocol 1 must not start seeing a third element.
      assert {:ok, _quoted} = GenServer.call(IntellijElixir.Quoter, @code)
    end

    test "answers a bare quote that warns while standard_error does not drain, and a compile after it" do
      # The quoter answers a quote in its own process, so a warning written to a console that has stopped draining
      # would suspend every later request with it.
      with_standard_error(spawn(fn -> Process.sleep(:infinity) end), fn ->
        assert {:ok, _quoted} = GenServer.call(IntellijElixir.Quoter, @warning_source, 2_000)
        assert {:ok, [], _events, _diagnostics} = compile("1 + 2", timeout: 2_000)
      end)
    end
  end

  describe "the {:quote, code} request" do
    test "reports a warning the source produced" do
      assert {:ok, _quoted, [{:warning, 1, @warning_column, @warning_message}]} =
               GenServer.call(IntellijElixir.Quoter, {:quote, @warning_source})
    end

    test "reports no diagnostics for a source that does not warn" do
      assert {:ok, quoted, []} = GenServer.call(IntellijElixir.Quoter, {:quote, @code})
      assert {:ok, quoted} == @quoted
    end

    test "reports no diagnostics for a source that warns and then fails to parse" do
      # Elixir discards the diagnostics it accumulated before a failure rather than reporting them
      # alongside it, on every supported release.
      assert {:error, _reason, []} =
               GenServer.call(IntellijElixir.Quoter, {:quote, @warning_source <> "\nfoo("})
    end

    test "reports no diagnostics for a source that raises" do
      assert {:raise, UnicodeConversionError, message, []} =
               GenServer.call(IntellijElixir.Quoter, {:quote, @raising})

      assert is_binary(message)
    end

    test "keeps every warning, in the order the source emitted them" do
      # Each line is the warning source verbatim, so every column matches @warning_column.
      source =
        Enum.map_join(~w[x y z], "\n", fn name -> String.replace(@warning_source, "x", name) end)

      assert {:ok, _quoted, diagnostics} =
               GenServer.call(IntellijElixir.Quoter, {:quote, source})

      assert [
               {:warning, 1, @warning_column, @warning_message},
               {:warning, 2, @warning_column, @warning_message},
               {:warning, 3, @warning_column, @warning_message}
             ] == diagnostics
    end

    test "does not leak diagnostics into the next request" do
      assert {:ok, _quoted, [_warning]} =
               GenServer.call(IntellijElixir.Quoter, {:quote, @warning_source})

      assert {:ok, _quoted, []} = GenServer.call(IntellijElixir.Quoter, {:quote, @code})
    end

    test "survives a raise" do
      pid = Process.whereis(IntellijElixir.Quoter)
      GenServer.call(IntellijElixir.Quoter, {:quote, @raising})

      assert Process.whereis(IntellijElixir.Quoter) == pid
      assert {:ok, _quoted, []} = GenServer.call(IntellijElixir.Quoter, {:quote, @code})
    end

    test "answers a quote that warns while standard_error does not drain, and a compile after it" do
      # The reply still carries the warning: only what Elixir prints is dropped.
      with_standard_error(spawn(fn -> Process.sleep(:infinity) end), fn ->
        assert {:ok, _quoted, [_ | _]} =
                 GenServer.call(IntellijElixir.Quoter, {:quote, @warning_source}, 2_000)

        assert {:ok, [], _events, _diagnostics} = compile("1 + 2", timeout: 2_000)
      end)
    end
  end

  describe "the {:quote, code, opts} request" do
    test "passes columns: to the parser" do
      assert {:ok, {:+, [line: 1, column: 3], [1, 2]}, []} ==
               GenServer.call(IntellijElixir.Quoter, {:quote, "1 + 2", [columns: true]})
    end

    test "passes token_metadata: to the parser" do
      assert {:ok, {:foo, meta, [1]}, []} =
               GenServer.call(IntellijElixir.Quoter, {:quote, "foo(1)", [token_metadata: true]})

      assert Keyword.fetch!(meta, :closing) == [line: 1]
    end

    test "passes both, as Elixir emits them on every supported release" do
      assert {:ok,
              {:__block__, [],
               [
                 {:a,
                  [
                    end_of_expression: [newlines: 1, line: 1, column: 2],
                    line: 1,
                    column: 1
                  ], nil},
                 {:b, [line: 2, column: 1], nil}
               ]}, []} ==
               GenServer.call(
                 IntellijElixir.Quoter,
                 {:quote, "a\nb", [columns: true, token_metadata: true]}
               )
    end

    test "replies as {:quote, code} does when given no options" do
      assert GenServer.call(IntellijElixir.Quoter, {:quote, @code}) ==
               GenServer.call(IntellijElixir.Quoter, {:quote, @code, []})
    end

    test "reports a warning the source produced" do
      assert {:ok, _quoted, [{:warning, 1, @warning_column, @warning_message}]} =
               GenServer.call(IntellijElixir.Quoter, {:quote, @warning_source, [columns: true]})
    end

    test "rejects an option it does not pass to the parser" do
      assert {:error, {:invalid_options, [existing_atoms_only: true]}, []} ==
               GenServer.call(
                 IntellijElixir.Quoter,
                 {:quote, @code, [columns: true, existing_atoms_only: true]}
               )
    end

    test "rejects an option value that is not a boolean" do
      assert {:error, {:invalid_options, [columns: 1]}, []} ==
               GenServer.call(IntellijElixir.Quoter, {:quote, @code, [columns: 1]})
    end

    test "rejects options that are not a keyword list whole, and survives them" do
      pid = Process.whereis(IntellijElixir.Quoter)
      improper = [{:columns, true} | :tail]

      assert {:error, {:invalid_options, ^improper}, []} =
               GenServer.call(IntellijElixir.Quoter, {:quote, @code, improper})

      assert {:error, {:invalid_options, %{columns: true}}, []} ==
               GenServer.call(IntellijElixir.Quoter, {:quote, @code, %{columns: true}})

      assert Process.whereis(IntellijElixir.Quoter) == pid
    end
  end

  describe "concurrent requests" do
    test "quotes overlap rather than queue behind a slow one" do
      slow = String.duplicate("1 + ", 200_000) <> "1"

      slow_task = Task.async(fn -> GenServer.call(IntellijElixir.Quoter, slow, 30_000) end)
      Process.sleep(10)

      {micros, {:ok, {:+, _, [1, 2]}}} =
        :timer.tc(fn -> GenServer.call(IntellijElixir.Quoter, "1 + 2") end)

      assert micros < 1_000_000
      assert {:ok, _} = Task.await(slow_task, 30_000)
    end

    test "many quotes at once each get their own reply" do
      replies =
        1..200
        |> Task.async_stream(
          fn n -> GenServer.call(IntellijElixir.Quoter, {:quote, "#{n} + 1"}) end,
          max_concurrency: 50
        )
        |> Enum.map(fn {:ok, reply} -> reply end)

      for {reply, n} <- Enum.with_index(replies, 1) do
        assert {:ok, {:+, _, [^n, 1]}, []} = reply
      end
    end
  end

  describe "the {:compile, code, opts} request" do
    test "replies with the probes' messages and the tracer's events, in arrival order" do
      ns = namespace()
      probe = Module.concat([ns, "Probe"])
      user = Module.concat([ns, "User"])

      assert {:ok, [:in_body], events, []} =
               compile(
                 probe_module(ns) <>
                   user_module(ns, "require #{ns}.Probe\n#{ns}.Probe.probe(:in_body)")
               )

      assert {:start, %Macro.Env{}} = List.first(events)
      assert {:stop, %Macro.Env{}} = List.last(events)

      assert [nil, probe, user] ==
               events |> Enum.map(fn {_event, env} -> env.module end) |> Enum.uniq()

      assert Enum.any?(
               events,
               &match?(
                 {{:remote_function, _meta, String, :upcase, 1}, %Macro.Env{module: ^user}},
                 &1
               )
             )
    end

    test "leaves no module it defined loaded" do
      ns = namespace()

      assert {:ok, _messages, _events, _diagnostics} =
               compile(probe_module(ns) <> user_module(ns, ""))

      refute :code.is_loaded(Module.concat([ns, "Probe"]))
      refute :code.is_loaded(Module.concat([ns, "User"]))
    end

    # On 1.13 to 1.16.1 such a module is traced only once, by its :on_module, when it is already loaded.
    test "unloads a module whose body traces nothing" do
      ns = namespace()

      assert {:ok, [], _events, []} = compile("defmodule #{ns}.Empty do\nend\n")
      refute :code.is_loaded(Module.concat([ns, "Empty"]))
    end

    test "still traces and unloads after compiled code resets the node's tracers" do
      assert {:ok, [], _events, _diagnostics} = compile("Code.put_compiler_option(:tracers, [])")

      ns = namespace()

      assert {:ok, [], [_ | _], _diagnostics} = compile(user_module(ns, ""))
      refute :code.is_loaded(Module.concat([ns, "User"]))
    end

    test "keeps what arrived before a raise, and unloads what it defined" do
      ns = namespace()

      code =
        probe_module(ns) <>
          user_module(ns, """
          require #{ns}.Probe
          #{ns}.Probe.probe(:before)
          raise "boom"
          """)

      user = Module.concat([ns, "User"])

      assert {{:raise, RuntimeError, "boom"}, [:before], events, _diagnostics} = compile(code)
      assert Enum.any?(events, &match?({_event, %Macro.Env{module: ^user}}, &1))
      refute :code.is_loaded(Module.concat([ns, "Probe"]))
    end

    test "unloads a module whose @after_compile raises once it is loaded" do
      ns = namespace()

      code =
        user_module(ns, """
        @after_compile __MODULE__
        def __after_compile__(_env, _bytecode), do: raise("after")
        """)

      assert {{:raise, RuntimeError, "after"}, [], _events, _diagnostics} = compile(code)
      refute :code.is_loaded(Module.concat([ns, "User"]))
    end

    test "answers a compile error with a raise" do
      ns = namespace()

      assert {{:raise, CompileError, message}, [], _events, _diagnostics} =
               compile(user_module(ns, "def f, do: undefined_var"))

      assert is_binary(message)
    end

    test "reports the warnings the compile emitted, from 1.15 on" do
      ns = namespace()

      assert {:ok, [], _events, diagnostics} = compile(user_module(ns, "def f(unused), do: :ok"))

      if @compile_diagnostics do
        assert [{:warning, 3, _column, message}] = diagnostics
        assert message =~ "unused"
      else
        assert [] == diagnostics
      end
    end

    test "stops a compile that outlives its timeout, keeping what arrived" do
      ns = namespace()

      code =
        probe_module(ns) <>
          user_module(ns, """
          require #{ns}.Probe
          #{ns}.Probe.probe(:before)
          IntellijElixir.Quoter.Probe.send(__ENV__, self())
          Process.sleep(:infinity)
          """)

      assert {:timeout, [:before, pid], _events, []} = compile(code, timeout: 200)
      refute Process.alive?(pid)
      refute :code.is_loaded(Module.concat([ns, "Probe"]))
    end

    test "never mixes the messages of compiles running at once" do
      compiles =
        for tag <- [:a, :b] do
          ns = namespace()

          code =
            user_module(ns, """
            for i <- 1..20 do
              IntellijElixir.Quoter.Probe.send(__ENV__, {#{inspect(tag)}, i})
              Process.sleep(5)
            end
            """)

          {tag, Module.concat([ns, "User"]), Task.async(fn -> compile(code) end)}
        end

      for {tag, module, task} <- compiles do
        assert {:ok, messages, events, _diagnostics} = Task.await(task, 30_000)
        assert messages == for(i <- 1..20, do: {tag, i})

        assert [nil, module] ==
                 events |> Enum.map(fn {_event, env} -> env.module end) |> Enum.uniq()
      end
    end

    test "keeps answering quote requests while a compile runs" do
      Process.register(self(), :quoter_test_compiling)

      task =
        Task.async(fn ->
          compile("send(:quoter_test_compiling, :compiling)\nProcess.sleep(1_000)")
        end)

      assert_receive :compiling, 5_000
      assert {:ok, _quoted, []} = GenServer.call(IntellijElixir.Quoter, {:quote, @code}, 500)
      assert nil == Task.yield(task, 0)
      assert {:ok, [], _events, []} = Task.await(task, 30_000)
    end

    test "answers a compile whose process is killed, and survives it" do
      pid = Process.whereis(IntellijElixir.Quoter)

      assert {{:raise, :exit, ":killed"}, [], _events, []} =
               compile("Process.exit(self(), :kill)")

      assert Process.whereis(IntellijElixir.Quoter) == pid
      assert {:ok, [], _events, []} = compile("1 + 2")
    end

    test "rejects an option it does not know" do
      assert {{:error, {:invalid_options, [bogus: true]}}, [], [], []} ==
               compile("1 + 2", bogus: true)
    end

    test "rejects a timeout that is not a positive integer" do
      assert {{:error, {:invalid_options, [timeout: 0]}}, [], [], []} ==
               compile("1 + 2", timeout: 0)
    end

    test "rejects a timeout longer than a timer can wait" do
      assert {{:error, {:invalid_options, [timeout: 4_294_967_296]}}, [], [], []} ==
               compile("1 + 2", timeout: 4_294_967_296)
    end

    test "rejects options that are not a keyword list whole, and survives them" do
      pid = Process.whereis(IntellijElixir.Quoter)

      assert {{:error, {:invalid_options, [{:timeout, 1} | :tail]}}, [], [], []} ==
               compile("1 + 2", [{:timeout, 1} | :tail])

      assert Process.whereis(IntellijElixir.Quoter) == pid
    end

    # Whether a failed redefinition leaves the old module loaded is Elixir's to decide, and it changed between
    # releases, so this replaces the module successfully.
    test "leaves a module loaded that was loaded before the compile defined it" do
      assert {:ok, [], _events, _diagnostics} =
               compile("defmodule #{inspect(Preexisting)} do\n  def here?, do: :replaced\nend\n")

      assert :replaced == Preexisting.here?()
    end

    test "answers a warning-heavy compile while standard_error does not drain" do
      # Before 1.15 every warning is a synchronous write to standard_error, so a console that has stopped draining
      # would hold the compile until its timeout.
      with_standard_error(spawn(fn -> Process.sleep(:infinity) end), fn ->
        assert {:ok, [], _events, _diagnostics} =
                 compile(warning_heavy(namespace()), timeout: 2_000)
      end)
    end

    test "drops a compile's output and passes other writes to standard_error on" do
      with_standard_error(recorder(self()), fn ->
        assert {:ok, [], _events, _diagnostics} =
                 compile(warning_heavy(namespace()), timeout: 2_000)

        IO.write(:stderr, "outside\n")
        assert_receive {:written, "outside\n"}, 1_000

        # A write the compile made would already have arrived: all end before the reply, on every release.
        assert [] == written()
      end)
    end

    test "restoring a replaced standard_error leaves the same device registered, and writable" do
      assert {:ok, _, _, _} = compile("1 + 2")
      registered = Process.whereis(:standard_error)

      with_standard_error(recorder(self()), fn -> assert {:ok, _, _, _} = compile("1 + 2") end)

      assert {:ok, _, _, _} = compile("1 + 2")
      assert registered == Process.whereis(:standard_error)
      assert :ok == IO.write(:stderr, "")
    end
  end

  describe "IntellijElixir.Quoter.Probe.send/2" do
    test "does nothing outside a compile" do
      assert :ok == IntellijElixir.Quoter.Probe.send(__ENV__, :unheard)
      refute_received :unheard
    end
  end

  describe "the :capabilities request" do
    test "reports the release answering and that capture works on it" do
      assert %{
               protocol: 3,
               elixir: elixir,
               otp: otp,
               mechanism: mechanism,
               warning_capture: true,
               compile_diagnostics: compile_diagnostics
             } = IntellijElixir.Quoter.capabilities()

      assert elixir == System.version()
      assert otp == List.to_string(:erlang.system_info(:otp_release))
      assert mechanism in [:with_diagnostics, :compiler_info, :compiler_pid]
      assert compile_diagnostics == @compile_diagnostics
    end
  end

  defp compile(code, opts \\ []) do
    GenServer.call(IntellijElixir.Quoter, {:compile, code, opts}, 30_000)
  end

  # Registers `device` as standard_error for `fun`, then puts back what was registered and stops `device`.
  defp with_standard_error(device, fun) do
    original = Process.whereis(:standard_error)
    Process.unregister(:standard_error)
    Process.register(device, :standard_error)

    try do
      fun.()
    after
      if Process.whereis(:standard_error), do: Process.unregister(:standard_error)
      Process.register(original, :standard_error)
      Process.exit(device, :kill)
    end
  end

  # A device that reports what it is asked to write to `test`, so a test can tell who wrote.
  defp recorder(test) do
    spawn(fn ->
      Stream.repeatedly(fn ->
        receive do
          {:io_request, from, reply_as, {:put_chars, _encoding, chars}} ->
            send(test, {:written, IO.chardata_to_string(chars)})
            send(from, {:io_reply, reply_as, :ok})
        end
      end)
      |> Stream.run()
    end)
  end

  defp written(acc \\ []) do
    receive do
      {:written, chars} -> written([chars | acc])
    after
      0 -> Enum.reverse(acc)
    end
  end

  # Warns from the compiling process (unused variables), and, on the releases that check or compile in other
  # processes, from those (an unused private function, an undefined remote call).
  defp warning_heavy(namespace) do
    functions = Enum.map_join(1..50, "\n", fn i -> "def f#{i}(a, b), do: :ok" end)

    """
    defmodule #{namespace}.WarningHeavy do
    #{functions}
    defp unused, do: :ok
    def g, do: Nope.missing()
    end
    """
  end

  # A namespace no other compile uses, so no two tests define the same module.
  defp namespace, do: "IntellijElixir.QuoterTest.Compiled#{System.unique_integer([:positive])}"

  # `probe(term)` reports `term`, as written, to the compile that expands it.
  defp probe_module(namespace) do
    """
    defmodule #{namespace}.Probe do
      defmacro probe(term) do
        IntellijElixir.Quoter.Probe.send(__CALLER__, term)
        :ok
      end
    end
    """
  end

  # `body` starts on line 3 of the returned source.
  defp user_module(namespace, body) do
    """
    defmodule #{namespace}.User do
      def upcase(string), do: String.upcase(string)
    #{body}
    end
    """
  end
end
