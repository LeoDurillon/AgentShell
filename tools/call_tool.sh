#!/bin/bash

WORKING_DIR="$(pwd)"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

NAME="$1"

if [ "$NAME" = "done" ]; then
    echo "✅ All tools executed successfully." >&2
    exit 0
fi

echo "🔧 Tool: $NAME" >&2
TOOL_LIST=$(ls $SCRIPT_DIR/function)

cd "$WORKING_DIR" || exit 1
TOOL_SCRIPT="$SCRIPT_DIR/function/$NAME.sh"

if [ ! -f "$TOOL_SCRIPT" ]; then
    echo "❌ Tool does not exist: $NAME" > /dev/tty
    echo "Tool not found: $NAME"
    exit 1
fi

echo "✅ Tool exists: $NAME" > /dev/tty

$SCRIPT_DIR/function/${NAME}.sh "$2"
