#!/usr/bin/env bash
# Starts the assembled release the way the IntelliJ Elixir build does (buildSrc/.../*QuoterPlatform.kt),
# asks the running Quoter to quote "1 + 2" and checks the answer.
set -euo pipefail

# prod unless MIX_ENV says otherwise, as intellij-elixir builds it (DEFAULT_MIX_ENV in buildSrc/.../MixEnvironment.kt).
rel=_build/${MIX_ENV:-prod}/rel/quoter/bin/quoter
if [[ ${OS:-} == Windows_NT ]]; then
  # No run_erl on Windows, so there is no daemon command.
  rel+=.bat
  "$rel" start > release.log 2>&1 &
else
  "$rel" daemon
fi
trap '"$rel" stop > /dev/null 2>&1 || true' EXIT

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

# Double quotes and |> do not survive being passed to the .bat.
result=$("$rel" rpc 'IO.inspect(GenServer.call(IntellijElixir.Quoter, ~s(1 + 2)))' | tr -d '\r') || true
echo "Quoter returned: $result"
[[ $result == "{:ok, {:+, [line: 1], [1, 2]}}" ]]
