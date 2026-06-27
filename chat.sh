#!/bin/bash

MODEL="gpt-5-mini"
ENDPOINT="https://api.individual.githubcopilot.com"
EDITOR_VERSION="vscode/1.107.0";
EDITOR_PLUGIN_VERSION="copilot-chat/0.35.0";
INTEGRATION_ID="vscode-chat";
USER_AGENT="GitHubCopilotChat/0.35.0"
TEMP_FILE="./copilot_token.json"
TOKEN=$(jq -r '.token' "$TEMP_FILE")
EXPIRES_AT=$(jq -r '.expires_at' "$TEMP_FILE")
NOW=$(date +%s)



if [ "$#" -lt 2 ]; then
    echo "Usage: $0 <system prompt> <file1> [file2 ...]"
    exit 1
fi

if [ "$NOW" -ge "$EXPIRES_AT" ]; then
    echo "❌ Token expiré depuis $(( (NOW - EXPIRES_AT) / 60 )) minutes. Lance: ./token_exchange.sh" >&2
    exit 1
fi
SYSTEM_PROMPT="$1"
shift

# Construire le tableau de messages avec jq
# jq --rawfile lit le fichier en entier et gère tous les caractères spéciaux
MESSAGES=$(jq -n --arg system "$SYSTEM_PROMPT" '[ { role: "system", content: $system } ]')

for file in "$@"; do
    if [ ! -f "$file" ]; then
        echo "File not found: $file"
        exit 1
    fi
    # --rawfile injecte le contenu brut du fichier sans aucun échappement manuel
    MESSAGES=$(echo "$MESSAGES" | jq \
        --arg path "$file" \
        --rawfile content "$file" \
        '. += [{ role: "user", content: ("<file path=\"\($path)\">\n```\n\($content)```\n</file>") }]')
done

# Construire le body final avec jq
BODY=$(jq -n \
    --arg model "$MODEL" \
    --argjson messages "$MESSAGES" \
    '{
        model: $model,
        messages: $messages,
        stream: true,
        temperature: 0.2
    }')


curl -sS -N -X POST "$ENDPOINT/chat/completions" \
    -H "Content-Type: application/json" \
    -H "Authorization: Bearer $TOKEN" \
    -H "User-Agent: $USER_AGENT" \
    -H "Editor-Version: $EDITOR_VERSION" \
    -H "Editor-Plugin-Version: $EDITOR_PLUGIN_VERSION" \
    -H "Copilot-Integration-Id: $INTEGRATION_ID" \
    -d "$BODY" \
| while IFS= read -r line; do
    [[ -z "$line" || "$line" == "data: [DONE]" ]] && continue
    [[ "${line:0:6}" != "data: " ]] && continue
    json="${line#data: }"
    chunk=$(printf '%s' "$json" | jq -rj 'select(.choices[0].delta.content != null) | .choices[0].delta.content' 2>/dev/null)
    [[ -n "$chunk" ]] && printf '%s' "$chunk"
done
echo
