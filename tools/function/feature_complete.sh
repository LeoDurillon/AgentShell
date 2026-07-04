#!/bin/bash

ARGS="$1"
SUMMARY=$(printf '%s' "$ARGS" | jq -r '.summary')
echo "✅ Feature complete:" > /dev/tty
echo "$SUMMARY" > /dev/tty
