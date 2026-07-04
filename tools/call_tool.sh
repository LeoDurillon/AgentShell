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

if [ $(echo ${TOOL_LIST} | grep -c "$NAME.sh") -eq 1 ]; then
    echo "✅ Tool exists: $NAME" >&2
else
    echo "❌ Tool does not exist: $NAME"
    exit 1
fi

cd "$WORKING_DIR" || exit 1
$SCRIPT_DIR/function/$NAME.sh "$2"
