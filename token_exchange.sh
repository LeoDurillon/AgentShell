#!/bin/bash

AUTH_TOKEN_PATH=~/.config/github-copilot/hosts.json
VSCODE_CLIENT_ID="Iv1.b507a08c87ecfe98";

EDITOR_VERSION="vscode/1.107.0";
EDITOR_PLUGIN_VERSION="copilot-chat/0.35.0";
INTEGRATION_ID="vscode-chat";
USER_AGENT="GitHubCopilotChat/0.35.0";

TOKEN=$(jq -r '."github.com".copilot.access_token' "$AUTH_TOKEN_PATH")

EXCHANGE_RESPONSE=$(curl -s "https://api.github.com/copilot_internal/v2/token" \
    -H "User-Agent: $USER_AGENT"\
    -H "Editor-Version: $EDITOR_VERSION"\
    -H "Editor-Plugin-Version: $EDITOR_PLUGIN_VERSION"\
    -H "Copilot-Integration-Id: $INTEGRATION_ID"\
    -H "Authorization: token $TOKEN");

if [ -z "$EXCHANGE_RESPONSE" ]; then
    echo "Error: No response from token exchange endpoint"
    echo $EXCHANGE_RESPONSE
    exit 1
fi

STATUS=$(echo "$EXCHANGE_RESPONSE" | jq -r '.status');

if [ $STATUS -eq 401 ]; then
    echo "Unhautorized exception from GitHub Copilot token exchange endpoint"
    echo "Removing the existing token"
    rm ${AUTH_TOKEN_PATH}
    echo "Restart app to authenticate again"

    exit 1
fi
if [ $STATUS -ne 200 ]; then
    echo "Error: Unexpected status code $STATUS from token exchange endpoint"
    echo "Response: $EXCHANGE_RESPONSE"
    exit 1
fi

TOKEN=$(echo "$EXCHANGE_RESPONSE" | jq -r '.token');
EXPIRES_AT=$(echo "$EXCHANGE_RESPONSE" | jq -r '.expires_at');
API_ENDPOINT=$(echo "$EXCHANGE_RESPONSE" | jq -r '.api_endpoint');


echo "GitHub Copilot token exchange successful"
echo "Expires at: $EXPIRES_AT"

echo "Set data in temp file"
TEMP_FILE="./copilot_token.json"

if [ -f "$TEMP_FILE" ]; then
    echo "Temp file already exists, removing it"
    rm "$TEMP_FILE"
fi

echo "{
  \"token\": \"$TOKEN\",
  \"expires_at\": \"$EXPIRES_AT\",
  \"api_endpoint\": \"$API_ENDPOINT\"
}" > "$TEMP_FILE"
