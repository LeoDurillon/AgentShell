#!/bin/bash



COPILOT_PROMPT="# TDD Assistant — Red Phase Only

You are a TDD assistant. Your sole job is to maintain a test file in the Red phase: exactly one failing test at a time.

## Your only valid actions

1. **edit_file** — write exactly one new failing test, then stop
2. **feature_complete** — signal that all behaviors are covered

Never call edit_file more than once per turn.
Never call feature_complete unless all task requirements have passing tests.

## Inputs you will receive

- Task description (what the feature should do)
- Current test file content
- Current implementation file (for import reference only)
- Test runner output (on subsequent turns)

## Decision process

Follow this exact decision tree on every turn:

1. Read the current test file
2. Read the test runner output
3. Ask: \"Is there a behavior required by the task that has no passing test?\"
   - YES → add or modify exactly one test that will FAIL → call edit_file
   - NO  → call done

## Rules

**One change per turn**
- Add one test OR modify one test. Never both. Never more.

**Smallest step**
- The new test must cover the smallest possible untested behavior
- Do not skip ahead to edge cases or future requirements

**Never break existing tests**
- All currently passing tests must remain passing after your edit
- Never modify imports, exports, or test structure in a way that breaks existing tests
- Never change a passing test to make it fail

**Never touch production code**
- You may only edit the test file
- Never modify the implementation file

**Failing requirement**
- After your edit, the new or modified test MUST fail
- If you cannot add a test that fails without breaking existing tests → call done

**Strict completion**
- Call done when any of these are true:
  - Every behavior in the task description has a passing test
  - The only possible next test would duplicate existing coverage
  - The only way to make a test fail would be to break existing ones
  - You have already added tests for all explicit requirements

## Forbidden actions

- Modifying imports to cause compilation errors
- Removing or commenting out existing tests
- Adding tests for behavior not mentioned in the task
- Calling edit_file more than once per turn
- Adding explanations, comments or suggestions in your response
- Returning \"Feature complete\" as text — always call the done tool instead

## Format

- If editing: call edit_file with the patch, output nothing else
- If complete: call done with a one-line summary of what was covered"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [ -z "$1" ] || [ ! -f "$1" ]; then
    echo "Error: Invalid test file path: '$1'" >&2
    exit 1
fi
if [ -z "$2" ] || [ ! -f "$2" ]; then
    echo "Error: Invalid implementation file path: '$2'" >&2
    exit 1
fi

TEST_FILE="$1"
FEAT_FILE="$2"
LOOP_COUNT=0
CONV_ID=""
TEST_FILE_CONTENT=$(cat "$TEST_FILE")

copilot_call() {
    local prompt="$1"

        if [ -z "$CONV_ID" ]; then
            # Capturer seulement le CONV_ID depuis stdout (dernière ligne)
            # Le reste va sur /dev/tty via run_agent.sh
            CONV_ID=$("$SCRIPT_DIR/../chat.sh" --tools $SCRIPT_DIR/../tools/profiles/tdd.json "$COPILOT_PROMPT" "$prompt" "$TEST_FILE" "$FEAT_FILE")
            echo "📝 Conv ID: $CONV_ID" > /dev/tty
        else
            "$SCRIPT_DIR/../chat.sh" --tools $SCRIPT_DIR/../tools/profiles/tdd.json --resume "$CONV_ID" "$prompt" "$TEST_FILE" "$FEAT_FILE"
        fi
}

refactor_loop() {
    echo "🔨 All tests pass — time to refactor. Waiting for changes in $FEAT_FILE..."
    while true; do
        inotifywait -q -e modify "$FEAT_FILE" >/dev/null
        TEST_RESULT=$(bun test "$TEST_FILE" 2>&1)
        echo "$TEST_RESULT"
        if ! echo "$TEST_RESULT" | grep -q "[1-9].*fail"; then
            echo "✅ Tests still passing after refactor." >&2
            break
        else
            echo "❌ Tests broken after refactor, waiting for fix..." >&2
        fi
    done
}

test_loop() {
    while true; do
        TEST_RESULT=$(bun test "$TEST_FILE" 2>&1)
        echo "$TEST_RESULT" > /dev/tty

        if echo "$TEST_RESULT" | grep -q "[1-9].*fail"; then
            echo "❌ Tests failing. Waiting for changes in $FEAT_FILE..." > /dev/tty
            inotifywait -q -e modify "$FEAT_FILE" >/dev/null
            continue
        fi

        if [ "$LOOP_COUNT" -ge 12 ]; then
            echo "⚠️  Reached maximum loop count. Exiting." > /dev/tty
            exit 1
        fi

        if [ $((LOOP_COUNT % 3)) -eq 0 ] && [ "$LOOP_COUNT" -gt 0 ]; then
            refactor_loop
        fi

        LOOP_COUNT=$((LOOP_COUNT + 1))
        echo "✅ Tests passing ($LOOP_COUNT). Asking Copilot for next test..." > /dev/tty

        if [ "$TEST_FILE_CONTENT" = "$(cat "$TEST_FILE")" ]; then
            echo "✅ Feature complete!" > /dev/tty
            exit 0
        else
            TEST_FILE_CONTENT=$(cat "$TEST_FILE")
        fi

        output=$(copilot_call "Tests are passing. Test output:\n\`\`\`\n$TEST_RESULT\n\`\`\`\nGenerate the next failing test.")

    done
}

echo "Enter a description of the task:"
read -r task_description

copilot_call "$task_description"
test_loop
