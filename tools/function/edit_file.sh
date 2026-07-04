#!/bin/bash

ARGS="$1"
FILE_PATH=$(printf '%s' "$ARGS" | jq -r '.path')
DIFF=$(printf '%s' "$ARGS" | jq -r '.diff')
echo "📝 Applying patch to $FILE_PATH" > /dev/tty
echo "📝 Diff content:\n$DIFF" > /dev/tty

apply_openai_patch() {
    local diff="$1"
    local current_file=""
    local in_hunk=0

    while IFS= read -r line; do
        case "$line" in
            "*** Begin Patch") ;;
            "*** End Patch")   ;;

            "*** Add File: "*)
                current_file="${line#\*\*\* Add File: }"
                mkdir -p "$(dirname "$current_file")"
                > "$current_file"
                echo "📄 Creating $current_file" > /dev/tty
                ;;

            "*** Update File: "*)
                current_file="${line#\*\*\* Update File: }"
                echo "✏️  Updating $current_file" > /dev/tty
                in_hunk=0
                ;;

            "*** Delete File: "*)
                local to_delete="${line#\*\*\* Delete File: }"
                rm -f "$to_delete"
                echo "🗑️  Deleted $to_delete" > /dev/tty
                ;;

            "@@"*)
                in_hunk=1
                ;;

            "+"*)
                printf '%s\n' "${line:1}" >> "$current_file"
                ;;

            "-"*)
                # Pour Update File : supprimer la ligne du fichier existant
                # Le format OpenAI ne donne pas de numéros de ligne
                # on utilise grep -v pour retirer la première occurrence
                local to_remove="${line:1}"
                local tmp=$(mktemp)
                awk -v line="$to_remove" '
                    !found && $0 == line { found=1; next }
                    { print }
                ' "$current_file" > "$tmp" && mv "$tmp" "$current_file"
                ;;

            " "*)
                # Ligne de contexte — vérifier qu'elle existe dans le fichier
                # (pas besoin d'écrire, elle y est déjà)
                ;;
        esac
    done <<< "$diff"

    echo "✅ Patch applied to $current_file" > /dev/tty
    echo "Patched $current_file"
}

apply_openai_patch "$DIFF"
