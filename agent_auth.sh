#!/bin/bash

WORKING_DIR="$(pwd)"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

AUTH_TOKEN_PATH=~/.config/github-copilot/hosts.json
VSCODE_CLIENT_ID="Iv1.b507a08c87ecfe98";

if [ ! -f "$AUTH_TOKEN_PATH" ]; then
  echo "GitHub Copilot authentication token not found. Process with authentication"

   CODES=$(curl -X POST "https://github.com/login/device/code" \
        -H "Accept: application/json" \
        -H "Content-Type: application/json" \
        -d "{\"client_id\":\"$VSCODE_CLIENT_ID\",\"scope\":\"read:user\"}");

    DEVICE_CODE=$(echo $CODES | jq -r '.device_code');
    USER_CODE=$(echo $CODES | jq -r '.user_code');
    INTERVAL=$(echo $CODES | jq -r '.interval');
     echo ""
     echo "┌──────────────────────────────────────────┐"
     echo "│  Connexion à GitHub Copilot              │"
     echo "│                                          │"
     echo "│  1. Va sur : https://github.com/login/device"
     echo "│  2. Entre le code : ${USER_CODE}              │"
     echo "│  3. Autorise l'accès                     │"
     echo "└─────────────────────────────────────────┘"
     echo ""

     while true; do
        sleep $INTERVAL
        RESPONSE=$(curl -s -X POST "https://github.com/login/oauth/access_token"\
            -H "Accept: application/json" \
            -H "Content-Type: application/json" \
            -d "{\"client_id\":\"$VSCODE_CLIENT_ID\",\"device_code\":\"$DEVICE_CODE\",\"grant_type\":\"urn:ietf:params:oauth:grant-type:device_code\"}");

        ACCESS_TOKEN=$(echo $RESPONSE | jq -r '.access_token');
        if [ "$ACCESS_TOKEN" != "null" ]; then
            echo "Access token received: $ACCESS_TOKEN"
            mkdir -p $(dirname "$AUTH_TOKEN_PATH")
            echo "{\"github.com\":{\"copilot\":{\"access_token\":\"$ACCESS_TOKEN\"}}}" > "$AUTH_TOKEN_PATH"
            echo "Access token saved to $AUTH_TOKEN_PATH"
            break
        fi

        ERROR=$(echo $RESPONSE | jq -r '.error');
        if [ "$ERROR" == "authorization_pending" ]; then
            echo "Waiting for user authorization..."
        elif [ "$ERROR" == "slow_down" ]; then
            echo "Slow down, waiting for user authorization..."
            INTERVAL=$((INTERVAL + 5))
        else
           UNKNOWN_ERROR=$(echo $RESPONSE | jq -r '.error_description');
            echo "Error: $UNKNOWN_ERROR"
            exit 1
        fi
    done
fi

$SCRIPT_DIR/token_exchange.sh
