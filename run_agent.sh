#!/bin/bash

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TEMP_FILE="$SCRIPT_DIR/copilot_token.json"
TOKEN=$(jq -r '.token' "$TEMP_FILE")
EXPIRES_AT=$(jq -r '.expires_at' "$TEMP_FILE")
NOW=$(date +%s)
TOOLS=${2:-[]}

MODEL="gpt-4o-mini"
ENDPOINT="https://api.individual.githubcopilot.com"
EDITOR_VERSION="vscode/1.107.0";
EDITOR_PLUGIN_VERSION="copilot-chat/0.35.0";
INTEGRATION_ID="vscode-chat";
USER_AGENT="GitHubCopilotChat/0.35.0"

DISPATCH="$SCRIPT_DIR/tools/call_tool.sh"

MESSAGES="$1"

# if no messages provided or not json should display usage
if [ "$#" -lt 1 ]; then
    echo "ERROR: Invalid Argument"
    echo "Usage: $0 <JSON msgs>"
    exit 1
fi

if ! printf '%s' "$1" | jq -e . >/dev/null 2>&1; then
    echo "ERROR: Messages must be valid json"
    echo "Usage: $0 <JSON msgs>"
    exit 1
fi

if [ "$NOW" -ge "$EXPIRES_AT" ]; then
    echo "❌ Token expired since $(( (NOW - EXPIRES_AT) / 60 )) minutes." > /dev/tty
    echo "Renewing token..." > /dev/tty
    $SCRIPT_DIR/agent_auth.sh

    if [ $? -ne 0 ]; then
        echo "❌ Failed to renew token." > /dev/tty
        exit 1
    fi

    TOKEN=$(jq -r '.token' "$TEMP_FILE")
    EXPIRES_AT=$(jq -r '.expires_at' "$TEMP_FILE")
fi


 while true; do
     BODY=$(jq -n \
         --arg model "$MODEL" \
         --argjson messages "$MESSAGES" \
         --argjson tools "$TOOLS" \
         '{
             model: $model,
             messages: $messages,
             tools: $tools,
             tool_choice: "auto",
             stream: true,
             temperature: 0.2
         }')

     finish_file=$(mktemp)
     name_file=$(mktemp)
     args_file=$(mktemp)
     id_file=$(mktemp)
     content_file=$(mktemp)

     while IFS= read -r line; do
         [[ -z "$line" || "$line" == "data: [DONE]" ]] && continue
         [[ "${line:0:6}" != "data: " ]] && continue
         json="${line#data: }"

         chunk=$(printf '%s' "$json" | jq -rj \
             'select(.choices[0].delta.content != null) | .choices[0].delta.content' 2>/dev/null)
         [[ -n "$chunk" ]] && { printf '%s' "$chunk" > /dev/tty; printf '%s' "$chunk" >> "$content_file"; }

         printf '%s' "$json" | jq -c '.choices[0].delta.tool_calls[]? // empty' 2>/dev/null \
         | while IFS= read -r tool_delta; do
             i=$(printf '%s' "$tool_delta" | jq -r '.index // 0')
             tname=$(printf '%s' "$tool_delta" | jq -rj '.function.name // empty')
             tid=$(printf '%s' "$tool_delta" | jq -rj '.id // empty')
             targs=$(printf '%s' "$tool_delta" | jq -rj '.function.arguments // empty')

             [[ -n "$tname" ]] && printf '%s' "$tname" >> "${name_file}_$i"
             [[ -n "$tid"   ]] && printf '%s' "$tid"   >> "${id_file}_$i"
             [[ -n "$targs" ]] && printf '%s' "$targs" >> "${args_file}_$i"
         done

         freason=$(printf '%s' "$json" | jq -rj \
             'select(.choices[0].finish_reason != null) | .choices[0].finish_reason' 2>/dev/null)
         [[ -n "$freason" ]] && echo "$freason" > "$finish_file"

     done < <(curl -sS -N -X POST "$ENDPOINT/chat/completions" \
         -H "Content-Type: application/json" \
         -H "Authorization: Bearer $TOKEN" \
         -H "User-Agent: $USER_AGENT" \
         -H "Editor-Version: $EDITOR_VERSION" \
         -H "Editor-Plugin-Version: $EDITOR_PLUGIN_VERSION" \
         -H "Copilot-Integration-Id: $INTEGRATION_ID" \
         -d "$BODY")
     echo

     TOOL_COUNT=0
     for f in "${name_file}_"*; do
         [[ -f "$f" ]] && TOOL_COUNT=$((TOOL_COUNT + 1))
    done

     FINISH_REASON=$(cat "$finish_file")
     TOOL_CALL_NAME=$(cat "$name_file")
     TOOL_CALL_ARGS=$(cat "$args_file")
     TOOL_CALL_ID=$(cat "$id_file")
     ASSISTANT_CONTENT=$(cat "$content_file")
     rm -f "$finish_file" "$name_file" "$args_file" "$id_file" "$content_file"

     case "$FINISH_REASON" in
         stop)
            printf '%s' "$MESSAGES"
            exit 0
            ;;
        tool_calls)
         ASSISTANT_CONTENT=$(cat "$content_file")

             # Construire le message assistant avec tous les tool calls
             TOOL_CALLS_JSON="[]"
             for i in $(seq 0 $((TOOL_COUNT - 1))); do
                 TID=$(cat "${id_file}_$i" 2>/dev/null)
                 TNAME=$(cat "${name_file}_$i" 2>/dev/null)
                 TARGS=$(cat "${args_file}_$i" 2>/dev/null)

                 TOOL_CALLS_JSON=$(printf '%s' "$TOOL_CALLS_JSON" | jq \
                     --arg id "$TID" \
                     --arg name "$TNAME" \
                     --arg args "$TARGS" \
                     '. += [{ id: $id, type: "function", function: { name: $name, arguments: $args } }]')
             done

             # Ajouter le message assistant avec tous les tool calls
             MESSAGES=$(printf '%s' "$MESSAGES" | jq \
                 --arg content "$ASSISTANT_CONTENT" \
                 --argjson tool_calls "$TOOL_CALLS_JSON" \
                 '. += [{ role: "assistant", content: $content, tool_calls: $tool_calls }]')

             # Exécuter chaque tool et ajouter son résultat
             DONE_CALLED=false
             for i in $(seq 0 $((TOOL_COUNT - 1))); do
                 TID=$(cat "${id_file}_$i" 2>/dev/null)
                 TNAME=$(cat "${name_file}_$i" 2>/dev/null)
                 TARGS=$(cat "${args_file}_$i" 2>/dev/null)

                 rm -f "${name_file}_$i" "${id_file}_$i" "${args_file}_$i"

                 if [[ "$TNAME" == "done" || "$TNAME" == "feature_complete" ]]; then
                     DONE_CALLED=true
                     TOOL_RESULT="acknowledged"
                 else
                     TOOL_RESULT=$("$DISPATCH" "$TNAME" "$TARGS")
                 fi

                 # Chaque tool call doit avoir sa propre réponse tool
                 MESSAGES=$(printf '%s' "$MESSAGES" | jq \
                     --arg tool_id "$TID" \
                     --arg result "$TOOL_RESULT" \
                     '. += [{ role: "tool", tool_call_id: $tool_id, content: $result }]')
             done

             if $DONE_CALLED; then
                 printf '%s' "$MESSAGES"
                 exit 0
             fi
             ;;
         *)
            echo "❌ Unexpected finish_reason: $FINISH_REASON"  > /dev/tty
            echo $FINISH_REASON > /dev/tty
            echo $TOOL_CALL_NAME > /dev/tty
            echo $TOOL_CALL_ARGS > /dev/tty
            echo $TOOL_CALL_ID > /dev/tty
            echo $ASSISTANT_CONTENT > /dev/tty

            echo $(printf '%s' "$MESSAGES")
            exit 1
            ;;
     esac
 done
