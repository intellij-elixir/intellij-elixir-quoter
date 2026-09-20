defmodule IntellijElixir.QuoterTest do
  use ExUnit.Case

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
  end

  describe "the :capabilities request" do
    test "reports the release answering and that capture works on it" do
      assert %{
               protocol: 2,
               elixir: elixir,
               otp: otp,
               mechanism: mechanism,
               warning_capture: true
             } = IntellijElixir.Quoter.capabilities()

      assert elixir == System.version()
      assert otp == List.to_string(:erlang.system_info(:otp_release))
      assert mechanism in [:with_diagnostics, :compiler_info, :compiler_pid]
    end
  end
end
