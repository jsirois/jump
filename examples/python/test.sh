# Copyright 2022 Science project contributors.
# Licensed under the Apache License, Version 2.0 (see LICENSE).

# shellcheck source=../common.sh
source "${COMMON}"
trap gc EXIT

check_cmd env

"${SCIE_JUMP}" "${LIFT}"
gc "${PWD}/pants" "${PWD}/.pants.d" "${PWD}/.pids"

# Observe initial install is un-perturbed by a binding command hostile setting for PEX_TOOLS (env
# var removal happens 1st).
time RUST_LOG=trace PEX_TOOLS=0 ./pants -V

# Observe subsequent short-circuiting of install activity.
time RUST_LOG=debug ./pants -V

# Use the built-in BusyBox functionality via env var.
SCIE_BOOT=repl ./pants -c 'from pants.util import strutil; print(strutil.__file__)'

# Verify targeted environment variable removal (=PYTHONPATH is zapped by the repl command).
SCIE_BOOT=repl PYTHONPATH=bob ./pants -c '
import os
assert "PYTHONPATH" not in os.environ, (
    f"""PYTHONPATH was not scrubbed: {os.environ["PYTHONPATH"]}"""
)
'

# Verify regex environment variable removal (PEX_.* is zapped by the default command and without
# that, the Pants venv PEX would try to execute foo.bar:baz instead of the `-c pants` console
# script).
PEX_MODULE="foo.bar:baz" ./pants -V

# Confirm boot bindings re-run successfully when the lift manifest changes - which allocates a new
# boot bindings directory.
jq '
setpath(["extra"]; 42)
| setpath(["scie", "lift", "name"]; "pants-extra")
' "${LIFT}" > lift.json
gc "${PWD}/lift.json" "${PWD}/pants-extra"
"${SCIE_JUMP}"
time RUST_LOG=debug ./pants-extra -V

# Verify dynamic env var selection.
SCIE_BOOT=repl ./pants -c 'import sys; assert (3, 9) == sys.version_info[:2]'
PYTHON_MINOR=8 SCIE_BOOT=repl ./pants -c 'import sys; assert (3, 8) == sys.version_info[:2]'
PYTHON_MINOR=9 SCIE_BOOT=repl ./pants -c 'import sys; assert (3, 9) == sys.version_info[:2]'

# Check non-utf8 env vars are handled: https://github.com/a-scie/jump/issues/105
# The PEX_.* zap directive in the lift manifest needs to traverse all env vars and we insert some
# non-utf8 env vars to ensure it skips past them.
env \
$'B\xa5R=FOO' \
$'FOO=B\xa5R' \
$'\xca\xfe\xba\xbe=B\xa5R' \
RUST_LOG=warn \
PEX_MODULE="foo.bar:baz" \
PYTHONVERBOSE=x \
SCIE_BOOT=repl \
  ./pants -c '
import os
assert "PEX_MODULE" in os.environ, "PEX_.* are only scrubbed in the venv binding command."
assert "PYTHONVERBOSE" not in os.environ, "Expected PYTHON.* to be scrubbed for the repl command."
'
