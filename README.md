IntelliJ Elixir Quoter
======================

[![Test](https://github.com/intellij-elixir/intellij-elixir-quoter/actions/workflows/test.yml/badge.svg)](https://github.com/intellij-elixir/intellij-elixir-quoter/actions/workflows/test.yml)

An Elixir release that gives [intellij-elixir](https://github.com/intellij-elixir/intellij-elixir), the
[Elixir](https://elixir-lang.org) plugin for [JetBrains](https://www.jetbrains.com) IDEs, Elixir's own quoted
form of a piece of code, so the plugin's tests can check that its parser quotes it the same way.

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
