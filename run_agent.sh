#!/bin/bash

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TEMP_FILE="$SCRIPT_DIR/copilot_token.json"
TOKEN=$(jq -r '.token' "$TEMP_FILE")
EXPIRES_AT=$(jq -r '.expires_at' "$TEMP_FILE")
NOW=$(date +%s)
TOOLS=$(cat "$SCRIPT_DIR/tools/tools.json")

MODEL="gpt-5-mini"
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
        [[ -n "$chunk" ]] && { printf '%s' "$chunk"; printf '%s' "$chunk" >> "$content_file"; }
          tname=$(printf '%s' "$json" | jq -rj \
            'select(.choices[0].delta.tool_calls != null) | .choices[0].delta.tool_calls[0].function.name // empty' 2>/dev/null)
        [[ -n "$tname" && ! -s "$name_file" ]] && printf '🔧 %s...' "$tname" > /dev/tty
        [[ -n "$tname" ]] && printf '%s' "$tname" >> "$name_file"
          tid=$(printf '%s' "$json" | jq -rj \
            'select(.choices[0].delta.tool_calls != null) | .choices[0].delta.tool_calls[0].id // empty' 2>/dev/null)
        [[ -n "$tid" ]] && printf '%s' "$tid" >> "$id_file"
          targs=$(printf '%s' "$json" | jq -rj \
            'select(.choices[0].delta.tool_calls != null) | .choices[0].delta.tool_calls[0].function.arguments // empty' 2>/dev/null)
        [[ -n "$targs" ]] && printf '%s' "$targs" >> "$args_file"
          freason=$(printf '%s' "$json" | jq -rj \
            'select(.choices[0].finish_reason != null) | .choices[0].finish_reason' 2>/dev/null)
        [[ -n "$freason" ]] && echo "$freason" > "$finish_file"

        [[ -n $chunk ]] && printf '%s' "$chunk" >&2

     done < <(curl -sS -N -X POST "$ENDPOINT/chat/completions" \
         -H "Content-Type: application/json" \
         -H "Authorization: Bearer $TOKEN" \
         -H "User-Agent: $USER_AGENT" \
         -H "Editor-Version: $EDITOR_VERSION" \
         -H "Editor-Plugin-Version: $EDITOR_PLUGIN_VERSION" \
         -H "Copilot-Integration-Id: $INTEGRATION_ID" \
         -d "$BODY")
     echo

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
             TOOL_RESULT=$("$DISPATCH" "$TOOL_CALL_NAME" "$TOOL_CALL_ARGS")
             DISPATCH_EXIT=$?

             if [[ "$TOOL_CALL_NAME" == "done" ]]; then
                 printf '%s' "$MESSAGES"
                 break
             fi

             echo "✅ Result: $TOOL_RESULT" > /dev/tty
             MESSAGES=$(printf '%s' "$MESSAGES" | jq \
                 --arg content "$ASSISTANT_CONTENT" \
                 --arg tool_id "$TOOL_CALL_ID" \
                 --arg tool_name "$TOOL_CALL_NAME" \
                 --arg tool_args "$TOOL_CALL_ARGS" \
                 --arg result "$TOOL_RESULT" \
                 '. += [
                     {
                         role: "assistant",
                         content: $content,
                         tool_calls: [{
                             id: $tool_id,
                             type: "function",
                             function: { name: $tool_name, arguments: $tool_args }
                         }]
                     },
                     { role: "tool", tool_call_id: $tool_id, content: $result }
                 ]')

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
