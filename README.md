IntelliJ Elixir Quoter
======================

[![Test](https://github.com/intellij-elixir/intellij-elixir-quoter/actions/workflows/test.yml/badge.svg)](https://github.com/intellij-elixir/intellij-elixir-quoter/actions/workflows/test.yml)

An Elixir release that gives [intellij-elixir](https://github.com/intellij-elixir/intellij-elixir), the
[Elixir](https://elixir-lang.org) plugin for [JetBrains](https://www.jetbrains.com) IDEs, Elixir's own quoted
form of a piece of code, so the plugin's tests can check that its parser quotes it the same way. It also compiles
code and reports what the compiler traced, so those tests can check the plugin's analysis against the compiler's.

# Supported versions

CI tests Elixir 1.11.4 on OTP 24.3.4.6 and Elixir 1.20.4 on OTP 29.0.6.

# Building the release

```sh
MIX_ENV=prod mix release
```

This assembles the release, including ERTS, in `_build/prod/rel/quoter`.

# Running the release

```sh
# Linux and macOS, in the background
_build/prod/rel/quoter/bin/quoter daemon

# Windows, in the foreground
_build\prod\rel\quoter\bin\quoter.bat start
```

The node is named `quoter` and uses the cookie `intellij-elixir-quoter`, unless the `RELEASE_NODE`,
`RELEASE_DISTRIBUTION` and `RELEASE_COOKIE` environment variables say otherwise. It registers
`IntellijElixir.Quoter`:

```elixir
GenServer.call(IntellijElixir.Quoter, "1 + 2")
#=> {:ok, {:+, [line: 1], [1, 2]}}
```

The reply is whatever `Code.string_to_quoted/1` returns, `{:ok, quoted}` or `{:error, reason}`, or
`{:raise, kind, message}` if it raises, throws or exits, where `kind` is the exception module, `:throw` or `:exit`.

## Diagnostics

Elixir writes the warnings it emits while quoting to the daemon's console, where a client cannot tell which
request produced them. Ask with `{:quote, code}` instead to get them back with the reply:

```elixir
GenServer.call(IntellijElixir.Quoter, {:quote, "x = ? "})
#=> {:ok, {:=, [line: 1], [{:x, [line: 1], nil}, 32]},
#=>  [{:warning, 1, 5, "found ? followed by code point 0x20 (space), please use ?\\s instead"}]}
```

Each diagnostic is `{severity, line, column, message}`, in the order Elixir emitted them, with duplicates kept.
`severity` is `:warning` or `:error`. `column` is `nil` on Elixir 1.11 and 1.12, which report no column.

A source Elixir rejects reports no diagnostics on every supported release, even when the tokenizer warned on an
earlier line, so `{:error, reason, []}` and `{:raise, kind, message, []}` are the only shapes those take.

Message wording is not stable across releases — some rules were reworded mid-range, and some do not exist in
older ones — so compare against the release under test rather than a recorded fixture.

## Parser options

`{:quote, code, opts}` quotes with the parser options `columns:` and `token_metadata:`, each a boolean, and replies
as `{:quote, code}` does:

```elixir
GenServer.call(IntellijElixir.Quoter, {:quote, "foo(1)", columns: true, token_metadata: true})
#=> {:ok, {:foo, [closing: [line: 1, column: 6], line: 1, column: 1], [1]}, []}
```

Any other option, or a value that is not a boolean, is rejected with `{:error, {:invalid_options, rejected}, []}`,
where `rejected` lists the offending entries, or is the whole of `opts` when that is not a keyword list.

## Compiling

`{:compile, code, opts}` compiles `code` with `Code.compile_string/2` in a process of its own, and replies with what
the compile reported:

```elixir
GenServer.call(IntellijElixir.Quoter, {:compile, code, timeout: 5_000}, 10_000)
#=> {status, messages, events, diagnostics}
```

The call's own timeout must be longer than `timeout:`, which is 5000 milliseconds unless given, or the call exits
before a compile that times out is answered.

* `status` is `:ok`; `{:raise, kind, message}` if the compile raises, throws or exits, as for quoting;
  `:timeout` if it outlives `timeout:` and is killed; or `{:error, {:invalid_options, rejected}}`, with every list
  empty, for any option other than `timeout:`, a positive integer of at most 4294967295, and `rejected` as for
  quoting.
* `messages` are the terms the compiled code reported with `IntellijElixir.Quoter.Probe.send/2`, in arrival order.
* `events` are the `{event, env}` pairs that a compiler tracer saw, unaltered and in arrival order. The shapes of the
  events differ between Elixir releases. Each `env` is a whole `Macro.Env`, about 2.5 KB when encoded, so a reply
  grows with the code compiled.
* `diagnostics` have the same shape as for quoting. They are captured on Elixir 1.15 and later only: before 1.15 the
  only hook is the parallel compiler's own protocol, which would change how the code compiles, so the list is
  always empty there. It is also empty on a timeout.

Whatever arrived before a raise or a timeout is kept, and compiles running at once never see each other's messages or
events. Every module the compile introduced is unloaded before the reply. A module that was already loaded when the
compile started defining it is left loaded, replaced or not, except on Elixir 1.13 to 1.16.1 when its new body traces
nothing.

The caller must not compile code that defines a module that is already loaded, or one that a compile running at the
same time defines, and no compiled code, a compile's own included, may change the node's compiler tracers. A compile
whose tracer was removed is traced by nothing and leaves its modules loaded.

To report a term, compiled code passes its environment, `__CALLER__` in a macro or `__ENV__` elsewhere:

```elixir
defmacro probe(term) do
  IntellijElixir.Quoter.Probe.send(__CALLER__, term)
  :ok
end
```

Each compile runs under a file name of its own, which is how the environment says which compile to report to. The
name changes on every compile, so a client should not compare `env.file` between compiles. Code that changes its
file, for example with `@file`, reports nowhere.

`{:compile, code, opts}` runs arbitrary code on the node. Start the release only where whoever can reach the node
could run that code anyway, as intellij-elixir's tests do, on the loopback interface with a cookie.

## Capabilities

```elixir
IntellijElixir.Quoter.capabilities()
#=> %{protocol: 3, elixir: "1.20.4", otp: "29", mechanism: :with_diagnostics, warning_capture: true,
#=>   compile_diagnostics: true}
```

`protocol` is 3 from v3.2.0, which added `{:quote, code, opts}` and `{:compile, code, opts}`, and 2 in v3.1.0.

`warning_capture: false` means diagnostics cannot be captured on this build: replies are still well formed, but
every diagnostics list is empty, which is indistinguishable from source that emitted nothing. A client that
compares diagnostics should fail rather than trust them.

`compile_diagnostics: false` means every `{:compile, code, opts}` reply has an empty diagnostics list, as on Elixir
before 1.15.

# Using with intellij-elixir

intellij-elixir's Gradle `test` task downloads, builds and starts the quoter itself, from the `quoterRepo` and
`quoterRef` in its `gradle.properties`. Its parser tests then call `IntellijElixir.Quoter` on that node. See
intellij-elixir's `CONTRIBUTING.md`.

# Development

`mise.toml` pins the development toolchain. CI runs these, and so can you:

```sh
mix format --check-formatted
mix credo --strict
mix dialyzer
mix test
MIX_ENV=prod mix release --overwrite && .github/scripts/smoke-test-release.sh
```
