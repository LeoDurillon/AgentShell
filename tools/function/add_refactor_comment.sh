#!/bin/bash
set -euo pipefail

ARGS="$1"

FILE_PATH=$(printf '%s' "$ARGS" | jq -r '.path')
LINE=$(printf '%s' "$ARGS" | jq -r '.line')
CATEGORY=$(printf '%s' "$ARGS" | jq -r '.category')
SUGGESTION=$(printf '%s' "$ARGS" | jq -r '.suggestion')

if [ -z "$FILE_PATH" ] || [ "$FILE_PATH" = "null" ]; then
    echo "❌ Missing required argument: path" > /dev/tty
    echo "Missing required argument: path"
    exit 1
fi

if ! [[ "$LINE" =~ ^[0-9]+$ ]] || [ "$LINE" -lt 1 ]; then
    echo "❌ Invalid line number: $LINE" > /dev/tty
    echo "Invalid line number: $LINE"
    exit 1
fi

case "$CATEGORY" in
    general)
        PREFIX="REFACTOR"
        ;;
        correctness|maintainability|readability|complexity|duplication|type|performance|security|convention|testability)
        PREFIX="REFACTOR($CATEGORY)"
        ;;
    *)
        echo "❌ Invalid refactor category: $CATEGORY" > /dev/tty
        echo "Invalid refactor category: $CATEGORY"
        exit 1
        ;;
esac

if [ -z "$SUGGESTION" ] || [ "$SUGGESTION" = "null" ]; then
    echo "❌ Missing required argument: suggestion" > /dev/tty
    echo "Missing required argument: suggestion"
    exit 1
fi

if [ ! -f "$FILE_PATH" ]; then
    echo "❌ File not found: $FILE_PATH" > /dev/tty
    echo "File not found: $FILE_PATH"
    exit 1
fi

LINE_COUNT=$(awk 'END { print NR }' "$FILE_PATH")
if [ "$LINE" -gt $((LINE_COUNT + 1)) ]; then
    echo "❌ Line $LINE is outside $FILE_PATH ($LINE_COUNT line(s))" > /dev/tty
    echo "Line $LINE is outside $FILE_PATH ($LINE_COUNT line(s))"
    exit 1
fi

# Keep the tool comment-only: normalize model-provided text to one line and
# strip any accidental leading REFACTOR marker so the tool owns the format.
SUGGESTION=$(printf '%s' "$SUGGESTION" \
    | tr '\r\n' ' ' \
    | sed -E 's/[[:space:]]+/ /g; s/^ *//; s/ *$//; s#^//[[:space:]]*##; s/^REFACTOR(\([^)]*\))?:[[:space:]]*//')

COMMENT="// $PREFIX: $SUGGESTION"
TMP_FILE=$(mktemp)

awk -v target="$LINE" -v comment="$COMMENT" '
    NR == target {
        match($0, /^[[:space:]]*/)
        print substr($0, RSTART, RLENGTH) comment
    }
    { print }
    END {
        if (target == NR + 1) {
            print comment
        }
    }
' "$FILE_PATH" > "$TMP_FILE"

mv "$TMP_FILE" "$FILE_PATH"

echo "💬 Added $COMMENT above line $LINE in $FILE_PATH" > /dev/tty
echo "Added refactor comment to $FILE_PATH:$LINE"
