# Changelog

## v3.2.1

### Bug Fixes
* [#16](https://github.com/intellij-elixir/intellij-elixir-quoter/issues/16) - [@sh41](https://github.com/sh41)
  * Quoting no longer waits for the console to drain. Every warning Elixir prints is a synchronous write to `:standard_error`, which under `run_erl` is a pty; when it stopped draining, a quote that warned held the quoter, and every request behind it, until it drained again. What Elixir prints while quoting is now dropped. The reply of `{:quote, code}` and `{:quote, code, opts}` still carries the warnings.
  * On Elixir 1.11 to 1.14, a compile no longer waits for the console either. It waited until its `timeout:` and answered `:timeout`. What it prints is dropped, and its diagnostics are still always empty there.

## v3.2.0

### Enhancements
* [#14](https://github.com/intellij-elixir/intellij-elixir-quoter/issues/14) - [@sh41](https://github.com/sh41)
  * `IntellijElixir.Quoter` answers `{:quote, code, opts}`, which quotes with the parser options `columns:` and `token_metadata:` and replies as `{:quote, code}` does. Any other option is rejected with `{:error, {:invalid_options, rejected}, []}`.
  * `IntellijElixir.Quoter` answers `{:compile, code, opts}`, which compiles `code` in a process of its own and replies `{status, messages, events, diagnostics}`: the terms the compiled code reported with `IntellijElixir.Quoter.Probe.send/2`, the `{event, env}` pairs a compiler tracer saw, and the diagnostics, each in arrival order. `status` is `:ok`, `{:raise, kind, message}`, `:timeout` after `timeout:` milliseconds (5000 unless given), or `{:error, {:invalid_options, rejected}}`. What arrived before a failure is kept, compiles running at once never see each other's messages or events, and every module the compile introduced is unloaded before the reply, while modules that were already loaded are left alone. Diagnostics are captured on Elixir 1.15 and later; before 1.15 the list is always empty, because capturing them would change how the code compiles.
  * `IntellijElixir.Quoter.capabilities/0` reports `protocol: 3`, and `compile_diagnostics:`, whether compiles report diagnostics on this release.

## v3.1.0

### Enhancements
* [#13](https://github.com/intellij-elixir/intellij-elixir-quoter/pull/13) - [@sh41](https://github.com/sh41)
  * `IntellijElixir.Quoter` answers a new `{:quote, code}` request with the diagnostics Elixir emitted while quoting that source: `{:ok, quoted, diagnostics}`, `{:error, reason, diagnostics}` or `{:raise, kind, message, diagnostics}`, where each diagnostic is `{severity, line, column, message}`. The bare binary request is unchanged, so an existing client keeps its reply shape.
  * `IntellijElixir.Quoter.capabilities/0` reports the protocol, the Elixir and OTP running the release, and whether capturing diagnostics works on it.

### Bug Fixes
* [#13](https://github.com/intellij-elixir/intellij-elixir-quoter/pull/13) - [@sh41](https://github.com/sh41)
  * Warnings emitted while quoting are no longer lost. They were written to the daemon's console, which the client cannot attribute to a request.
  * The release smoke test starts the release the way intellij-elixir does, as a long name on loopback, under a node name and cookie of its own. It took the release's defaults, so it exercised something the plugin never does, and a leftover node holding the fixed name stopped it starting at all.

## v3.0.0

### Enhancements
* [#11](https://github.com/intellij-elixir/intellij-elixir-quoter/pull/11) - [@sh41](https://github.com/sh41)
  * Build the release with `mix release` instead of Distillery.
  * Replace deprecated APIs such as `Supervisor.Spec` and `Mix.Config`.
  * Run CI on GitHub Actions.
* [#12](https://github.com/intellij-elixir/intellij-elixir-quoter/pull/12) - [@sh41](https://github.com/sh41)
  * CI tests Elixir 1.11.4 (OTP 24.3.4.6) and 1.20.4 (OTP 29.0.6), the newest on Linux, Windows and macOS, and smoke tests the `prod` release on each.

### Bug Fixes
* [#11](https://github.com/intellij-elixir/intellij-elixir-quoter/pull/11) - `IntellijElixir.Quoter` replies `{:raise, kind, message}` when `Code.string_to_quoted/1` raises, throws or exits, instead of crashing. - [@sh41](https://github.com/sh41)

### Incompatible Changes
* [#11](https://github.com/intellij-elixir/intellij-elixir-quoter/pull/11) - [@sh41](https://github.com/sh41)
  * Requires Elixir >= 1.11.
  * Build with `MIX_ENV=prod mix release`; Distillery's `--env` is gone.
  * `start` runs the release in the foreground; use `daemon` for the background.
  * The node defaults to a short name instead of `intellij_elixir@127.0.0.1`.
* [#12](https://github.com/intellij-elixir/intellij-elixir-quoter/pull/12) - Rename the application and release from `intellij_elixir` to `quoter`: the launcher is `_build/prod/rel/quoter/bin/quoter`, the node defaults to `quoter` and the cookie is `intellij-elixir-quoter`. - [@sh41](https://github.com/sh41)

## v2.1.0

### Enhancements
* [#7](https://github.com/KronicDeth/intellij_elixir/pull/7) - [@KronicDeth](https://github.com/KronicDeth)
  * Update dependencies
    * `credo` `0.9.3` => `1.0.0`
    * `ex_doc` `0.19.0` => `0.19.1`

### Bug Fixes
* [#7](https://github.com/KronicDeth/intellij_elixir/pull/7) - [@KronicDeth](https://github.com/KronicDeth)
  * Remove ignored project files
  * Update distillery to `2.0.12` for Elixir `1.7..4` compatibility.

## v2.0.0

### Enhancements
* [#6](https://github.com/KronicDeth/intellij_elixir/pull/6) - Update dependencies for Elixir 1.7.1 - [@KronicDeth](https://github.com/KronicDeth)

### Incompatible Changes
* [#6](https://github.com/KronicDeth/intellij_elixir/pull/6) - Requires Elixir >= 1.7 - [@KronicDeth](https://github.com/KronicDeth)

## v1.0.0

### Enhancements
* [#5](https://github.com/KronicDeth/intellij_elixir/pull/5) - [@KronicDeth](https://github.com/KronicDeth)
  * Switch from `exrm` to `distillery` adds support for Elixir 1.5.
  * Add `credo`
    * Run `credo` checks on CodeClimate.
  * Add `dialyxir`
    * Run `dialyxir` on Travis CI.
  * Build matrix for Elixir 1.3 - 1.5.

### Incompatible Changes
* [#5](https://github.com/KronicDeth/intellij_elixir/pull/5) - Switch from `exrm` to `distillery` drops support for Elixir < 1.3. - [@KronicDeth](https://github.com/KronicDeth)

## v0.1.1

### Enhancements
  * [#4](https://github.com/KronicDeth/intellij_elixir/pull/4) - Increase restart limit to 1000 restart per 4 seconds from the default 3 restarts per 5 seconds - [@KronicDeth](https://github.com/KronicDeth)

## v0.1.0

### Incompatible Changes
  * [#2](https://github.com/KronicDeth/intellij_elixir/pull/2) - `IntellijElixir.Quoter` implements `handle_call` instead of `handle_info` - [@KronicDeth](https://github.com/KronicDeth)
