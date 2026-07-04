#!/bin/bash

ARGS="$1"
SUMMARY=$(printf '%s' "$ARGS" | jq -r '.summary')
echo "✅ All tool executed successfully:" > /dev/tty
echo "$SUMMARY" > /dev/tty
