#!/usr/bin/env bash
# Starts the assembled release the way the IntelliJ Elixir build does (buildSrc/.../*QuoterPlatform.kt),
# asks the running Quoter to quote "1 + 2" and checks the answer.
set -euo pipefail

# prod unless MIX_ENV says otherwise, as intellij-elixir builds it (DEFAULT_MIX_ENV in buildSrc/.../MixEnvironment.kt).
rel=_build/${MIX_ENV:-prod}/rel/quoter/bin/quoter

# Matches buildSrc/.../QuoterPlatform.kt getReleaseEnvironment. `pid`, `rpc` and `stop` below address
# the node by name, so a name of this run's own keeps a leftover or concurrent node from answering
# for it or holding its name. Exported, so the backgrounded `start` and the trap agree.
export RELEASE_DISTRIBUTION=name
export RELEASE_NODE="quoter_smoke_$$_${RANDOM}@127.0.0.1"
export RELEASE_COOKIE="quoter-smoke-$$-${RANDOM}"

# Naming the node @127.0.0.1 does not narrow its listener, and binding every interface is what makes
# Windows Firewall prompt for the release's erl.exe. Appended because erlexec reads one ERL_AFLAGS.
export ERL_AFLAGS="${ERL_AFLAGS:-} -kernel inet_dist_use_interface {127,0,0,1}"

echo "Quoter node: $RELEASE_NODE"
start_job=
if [[ ${OS:-} == Windows_NT ]]; then
  # No run_erl on Windows, so there is no daemon command. Output goes to a file rather than a pipe
  # nothing reads, which would block the node once the buffer filled.
  rel+=.bat
  "$rel" start > release.log 2>&1 &
  start_job=$!
else
  "$rel" daemon
fi

# `stop` is what ends the node: on Windows the backgrounded job is the .bat wrapper, and reaping it
# does not reap the erl.exe it spawned.
cleanup() {
  "$rel" stop > /dev/null 2>&1 || true
  [[ -n $start_job ]] && kill "$start_job" 2> /dev/null || true
}
trap cleanup EXIT

# The .bat exit status is unreliable and boot warnings can precede the pid, so take the last numeric line.
quoter_pid=
for _ in $(seq 20); do
  quoter_pid=$("$rel" pid 2> /dev/null | tr -d '\r' | grep -E '^[0-9]+$' | tail -n 1) || true
  [[ -n $quoter_pid ]] && break
  sleep 0.5
done
if [[ -z $quoter_pid ]]; then
  echo "Quoter failed to start" >&2
  [[ -f release.log ]] && cat release.log >&2
  exit 1
fi

# `rpc` prints whatever the node reports before the answer - an unparsable line in the machine's
# hosts file is enough - so the answer is the last non-empty line.
answer() {
  "$rel" rpc "$1" | tr -d '\r' | grep -v '^[[:space:]]*$' | tail -n 1
}

# Double quotes and |> do not survive being passed to the .bat.
result=$(answer 'IO.inspect(GenServer.call(IntellijElixir.Quoter, ~s(1 + 2)))') || true
echo "Quoter returned: $result"
[[ $result == "{:ok, {:+, [line: 1], [1, 2]}}" ]]

# `match?/2` keeps the expected shape inside Elixir, so the column - which Elixir 1.11 and 1.12 do
# not report - need not be restated here.
diagnosed=$(answer 'IO.puts(match?({:ok, _quoted, [{:warning, 1, _column, _message}]}, GenServer.call(IntellijElixir.Quoter, {:quote, ~s(x = ? )})))') || true
echo "Quoter reported a diagnostic: $diagnosed"
[[ $diagnosed == "true" ]]

# A hook that stopped capturing would answer every request with an empty diagnostics list, which
# reads as source that emitted nothing.
captures=$(answer 'IO.puts(IntellijElixir.Quoter.capabilities().warning_capture)') || true
echo "Quoter reported warning capture: $captures"
[[ $captures == "true" ]]
