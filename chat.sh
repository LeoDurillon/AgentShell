#!/bin/bash

WORKING_DIR="$(pwd)"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

CONV_DIR="$SCRIPT_DIR/conversations"
mkdir -p "$CONV_DIR"


load_messages() {
    local conv_id="$1"
    local conv_file="$CONV_DIR/$conv_id.json"
    echo "🔄 Loading conversation: $conv_id" > /dev/tty
    if [[ -f "$conv_file" ]]; then
        cat "$conv_file"
    fi

}

build_messages_with_files() {
    local base_messages="$1"
    local prompt="$2"
    shift 2
    local files=("$@")

    local messages="$base_messages"

    for file in "${files[@]}"; do
        if [[ -f "$file" ]]; then
            filename=$(basename "$file")

            if [[ "$filename" =~ ^(CLAUDE|AGENTS|INSTRUCTIONS|\.cursorrules)(\.md)?$ ]]; then
                tag="instructions"
                role="system"
                content_wrap="<instructions path=\"\($path)\">\n\($content)\n</instructions>"
            else
                tag="file"
                role="user"
                content_wrap="<file path=\"\($path)\">\n\`\`\`\n\($content)\`\`\`\n</file>"
            fi

            local already_present
            already_present=$(printf '%s' "$messages" | jq \
                --arg path "$file" \
                --arg tag "$tag" \
                'any(.[];
                    .content != null and
                    (.content | type) == "string" and
                    (.content | startswith("<" + $tag + " path=\"" + $path + "\""))
                )')

            if [[ "$already_present" == "true" ]]; then
                messages=$(printf '%s' "$messages" | jq \
                    --arg path "$file" \
                    --arg tag "$tag" \
                    --rawfile content "$file" \
                    'map(
                        if (.content != null and
                            (.content | type == "string") and
                            startswith("<" + $tag + " path=\"" + $path + "\""))
                        then .content = ("<" + $tag + " path=\"" + $path + "\">\n```\n" + $content + "```\n</" + $tag + ">")
                        else .
                        end
                    )')
                echo "🔄 Updated $file in context" > /dev/tty
            else
                messages=$(printf '%s' "$messages" | jq \
                    --arg path "$file" \
                    --arg role "$role" \
                    --arg tag "$tag" \
                    --rawfile content "$file" \
                    '. += [{
                        role: $role,
                        content: ("<" + $tag + " path=\"" + $path + "\">\n```\n" + $content + "```\n</" + $tag + ">")
                    }]')
                echo "📄 Added $file to context" > /dev/tty
            fi
        else
            echo "⚠️  File not found, skipping: $file" > /dev/tty
        fi
    done

    messages=$(printf '%s' "$messages" | jq \
        --arg prompt "$prompt" \
        '. += [{ role: "user", content: $prompt }]')

    printf '%s' "$messages"
}

save_messages() {
    local conv_id="$1"
    local messages="$2"
    printf '%s' "$messages" > "$CONV_DIR/$conv_id.json"
}

list_conversations() {
    ls "$CONV_DIR" 2>/dev/null | sed 's/\.json$//'
}

delete_conversation() {
    local conv_id="$1"
    rm -f "$CONV_DIR/$conv_id.json"
    echo "🗑️  Conversation $conv_id deleted"
}

usage() {
    echo "Usage:"
    echo "  $0 <system_prompt> <prompt> [file1 file2 ...]              — nouvelle conversation"
    echo "  $0 --resume <conv_id> <prompt> [file1 ...]  — reprendre une conversation"
    echo "  $0 --list                                   — lister les conversations"
    echo "  $0 --delete <conv_id>                       — supprimer une conversation"
    exit 1
}

cd $WORKING_DIR
TOOLS=""
if [[ "$1" = "--tools" ]]; then
    if [ ! -f $2 ]; then
        echo "⚠️  Tools file not found: $2" > /dev/tty
        exit 1
    fi
    TOOLS=$(cat "$2")
    shift 2
fi

case "$1" in
    --list)
        echo "📋 Conversations:" > /dev/tty
        list_conversations | while read -r id; do
            turns=$(jq 'length' "$CONV_DIR/$id.json")
            echo "  $id  ($turns messages)" > /dev/tty
        done
        ;;

    --delete)
        [[ -z "$2" ]] && usage
        delete_conversation "$2"
        ;;

    --resume)
        [[ -z "$2" || -z "$3" ]] && usage
        CONV_ID="$2"
        PROMPT="$3"
        shift 3
        FILES=("$@")

        if [[ ! -f "$CONV_DIR/$CONV_ID.json" ]]; then
            echo "❌ Conversation not found: $CONV_ID" > /dev/tty
            exit 1
        fi

        echo "📂 Resuming conversation: $CONV_ID" > /dev/tty
        BASE_MESSAGES=$(load_messages "$CONV_ID")
        MESSAGES=$(build_messages_with_files "$BASE_MESSAGES" "$PROMPT" "${FILES[@]}")
        FINAL_MESSAGES=$($SCRIPT_DIR/run_agent.sh "$MESSAGES" "$TOOLS")
        save_messages "$CONV_ID" "$FINAL_MESSAGES"

        LAST_RESPONSE=$(printf '%s' "$FINAL_MESSAGES" | jq -r 'reverse | map(select(.role == "assistant")) | first | .content // ""')
        echo "$LAST_RESPONSE"
        ;;

    *)
        [[ -z "$2" ]] && usage
        SYSTEM_PROMPT="$1"
        PROMPT="$2"
        shift 2
        FILES=("$@")

        CONV_ID=$(date +%s%N)
        echo "🆕 New conversation: $CONV_ID" > /dev/tty

        BASE_MESSAGES=$(jq -n --arg system "$SYSTEM_PROMPT" \
                '[{ role: "system", content: $system }]')

        MESSAGES=$(build_messages_with_files "$BASE_MESSAGES" "$PROMPT" "${FILES[@]}")
        echo "💬 Sending messages to agent..." > /dev/tty
        FINAL_MESSAGES=$($SCRIPT_DIR/run_agent.sh "$MESSAGES" "$TOOLS")
        save_messages "$CONV_ID" "$FINAL_MESSAGES"

        echo "" > /dev/tty
        echo "💾 Conv ID: $CONV_ID" > /dev/tty
        echo $CONV_ID
        ;;
esac
