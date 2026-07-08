#!/bin/bash
ARGS="$1"
FILE_PATH=$(printf '%s' "$ARGS" | jq -r '.path')

if [ ! -f "$FILE_PATH" ]; then
    # Fichier nouveau → le créer
    mkdir -p "$(dirname "$FILE_PATH")"
    touch "$FILE_PATH"
    echo "📄 Created $FILE_PATH" > /dev/tty
fi

echo "✏️  Editing $FILE_PATH" > /dev/tty

# Trier les opérations du bas vers le haut pour préserver les numéros de ligne
OPERATIONS=$(printf '%s' "$ARGS" | jq -c '[.operations | sort_by(.line) | reverse[]]')

while IFS= read -r op; do
    TYPE=$(printf '%s' "$op" | jq -r '.type')
    LINE=$(printf '%s' "$op" | jq -r '.line')
    CONTENT=$(printf '%s' "$op" | jq -r '.content // ""')

    echo "  → $TYPE line $LINE" > /dev/tty

    case "$TYPE" in
        insert)
            ESCAPED=$(printf '%s' "$CONTENT" | sed 's/[\\&]/\\&/g; s/$/\\/')
            sed -i "${LINE}i\\${ESCAPED}" "$FILE_PATH"
            ;;
        replace)
            ESCAPED=$(printf '%s' "$CONTENT" | sed 's/[\/&\\]/\\&/g')
            sed -i "${LINE}s/.*/${ESCAPED}/" "$FILE_PATH"
            ;;
        delete)
            sed -i "${LINE}d" "$FILE_PATH"
            ;;
        *)
            echo "❌ Unknown operation type: $TYPE" > /dev/tty
            ;;
    esac
done <<< "$(printf '%s' "$OPERATIONS" | jq -c '.[]')"

echo "✅ Edited $FILE_PATH"
