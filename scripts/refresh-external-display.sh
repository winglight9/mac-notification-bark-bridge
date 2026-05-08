#!/bin/zsh

set -euo pipefail

SCRIPT_DIR=${0:A:h}
ROOT_DIR=${SCRIPT_DIR:h}
TOOL_PATH="$ROOT_DIR/build/display-refresh/refresh-external-display"
BUILD_SCRIPT="$SCRIPT_DIR/build-display-refresh-tool.sh"

/usr/bin/caffeinate -u -t 2 >/dev/null 2>&1 || true

if [[ ! -x "$TOOL_PATH" ]]; then
  "$BUILD_SCRIPT" >/dev/null
fi

exec "$TOOL_PATH" "$@"
