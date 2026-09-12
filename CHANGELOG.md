# Changelog

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
