#!/bin/bash
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

COPILOT_PROMPT="You are a senior code reviewer for this repository.

Your job is to review the target file and add inline REVIEW comments directly
above code that deserves human attention.

You are not a fixer. Do not rewrite, replace, delete, or move code.
Only insert comments using the add_review_comment tool.

Static analysis output is only a hint. Do not limit your review to tool output.
Inspect the code itself.

Comment format is handled by the tool:
- REVIEW(correctness)
- REVIEW(maintainability)
- REVIEW(readability)
- REVIEW(complexity)
- REVIEW(duplication)
- REVIEW(type)
- REVIEW(performance)
- REVIEW(security)
- REVIEW(convention)
- REVIEW(testability)

Review checklist:
- Correctness: edge cases, async errors, null/empty states, invalid inputs
- Maintainability: coupling, unclear responsibilities, hard-to-change design
- Readability: unclear names, hidden intent, confusing control flow
- Complexity: deep nesting, long functions, complex expressions
- Duplication: repeated logic or missing existing helper
- Type safety: unsafe casts, broad types, impossible states
- Performance: unnecessary repeated work on hot paths
- Security: unsafe input handling, secret exposure, injection risks
- Convention: mismatch with guidelines or existing codebase patterns
- Testability: important behavior hard to isolate or verify

Rules:
- Add only specific, actionable comments.
- Do not add generic best-practice comments.
- Do not nitpick formatting unless it violates project conventions.
- Prioritize correctness and maintainability over style.
- For convention comments, first verify the convention from guidelines or
  existing code using read/search tools.
- Prefer fewer high-value comments over many low-value comments.
- If no meaningful comments exist, call done."

if [ -z "$1" ]; then
    echo "Usage: $0 <file_path> [conv_id]"
    exit 1
fi

if [ ! -f "$1" ]; then
    echo "File not found: $1"
    exit 1
fi

# Vérifier les outils requis
MISSING_TOOLS=()
command -v tsc     >/dev/null 2>&1 || MISSING_TOOLS+=("tsc (typescript)")
command -v oxlint  >/dev/null 2>&1 || MISSING_TOOLS+=("oxlint")
command -v jscpd   >/dev/null 2>&1 || MISSING_TOOLS+=("jscpd")
command -v lizard  >/dev/null 2>&1 || MISSING_TOOLS+=("lizard")

if [ ${#MISSING_TOOLS[@]} -gt 0 ]; then
    echo "❌ Missing required tools:"
    for tool in "${MISSING_TOOLS[@]}"; do
        echo "   - $tool"
    done
    echo ""
    echo "Install missing tools and retry."
    exit 1
fi
FIRST_ARG="$1"
FILE=""
FILES=""
CONV_ID=""
case "$FIRST_ARG" in
    --help|-h)
        echo "Usage: $0 <file_path> [conv_id]"
        echo "Usage: $0 --resume [conv_id] <file_path>"
        echo "  <file_path>: Path to the file to analyze and refactor"
        echo "  [conv_id]: Optional conversation ID to resume an existing refactor session"
        exit 0
        ;;
    --resume)
        if [ -z "$2" ]; then
            echo "Error: --resume requires a conversation ID"
            exit 1
        fi
        CONV_ID="$2"
        shift 2
        FILE="$1"
        ;;
    *)
        FILE="$1"
esac

FILE_NAME=$(basename "$FILE")

EXISTING=$(grep -c "// REFACTOR" "$FILE" 2>/dev/null || echo "0")

if [ "$EXISTING" -gt 0 ]; then
    echo "❌ Pre-existing REFACTOR comments found ($EXISTING occurrence(s)) in $FILE_NAME"
    echo "   Remove all '// REFACTOR' comments before running the refactor agent."
    exit 1
fi

echo "🔍 Analyzing $FILE_NAME..." > /dev/tty

echo "  → typecheck" > /dev/tty

find_closest_tsconfig() {
    local dir

    dir="$(dirname "$(realpath "$1")")"

    while [[ "$dir" != "/" ]]; do
        if [[ -f "$dir/tsconfig.json" ]]; then
            printf '%s\n' "$dir/tsconfig.json"
            return 0
        fi

        dir="$(dirname "$dir")"
    done

    return 1
}

TSCONFIG=$(find_closest_tsconfig "$FILE")
if [[ -z "$TSCONFIG" ]]; then
    echo "❌ No tsconfig.json found"
    exit 1
fi

echo "  → using tsconfig: $TSCONFIG" > /dev/tty


TYPESCRIPT_RESULT=$(
tsc --noEmit --skipLibCheck -p "$TSCONFIG" 2>&1 |
grep "^$FILE" |
sed -E '
s#^(.*)\(([0-9]+),([0-9]+)\): error (TS[0-9]+): (.*)$#- ❌ Line \2, Col \3 (\4)\n  \5#
'
)
echo "  → linter" > /dev/tty
LINTER_RESULT=$(oxlint "$FILE" -f agent 2>&1)

echo "  → duplication" > /dev/tty
JSCPD_RESULT=$(jscpd . --reporters ai 2>/dev/null \
    | grep "$FILE_NAME")

echo "  → complexity" > /dev/tty
LIZARD_RESULT=$(
lizard -w -C12 -L120 -a5 "$FILE" |
awk '
/!!!!/ {
printf "- Function: %s\n", $7
printf "  - NLOC: %s\n", $1
printf "  - CCN: %s\n", $2
printf "  - Tokens: %s\n", $3
printf "  - Params: %s\n", $4
printf "  - Length: %s\n", $5
}
'
)

FRAMEWORK_RESULT=$($SCRIPT_DIR/../queries/summary.sh "$FILE")

TYPESCRIPT_RESULT=${TYPESCRIPT_RESULT:-"✅ No TypeScript diagnostics"}
LINTER_RESULT=${LINTER_RESULT:-"✅ No lint diagnostics"}
JSCPD_RESULT=${JSCPD_RESULT:-"✅ No duplicate code detected"}
LIZARD_RESULT=${LIZARD_RESULT:-"✅ No complexity threshold exceeded"}

TOOL_OUTPUT="# Review Context

## File

$FILE

## Static Analysis

### TypeScript

$TYPESCRIPT_RESULT

### Lint

$LINTER_RESULT

### Duplication

$JSCPD_RESULT

### Complexity

$LIZARD_RESULT

$FRAMEWORK_RESULT
"

echo "  → sending to refactor agent..." > /dev/tty
echo $TOOL_OUTPUT

if [ -z "$CONV_ID" ]; then
    # Nouvelle conversation → stdout = conv_id
    CONV_ID=$("$SCRIPT_DIR/../chat.sh" --tools $SCRIPT_DIR/../tools/profiles/refactor.json "$COPILOT_PROMPT" "$TOOL_OUTPUT" $@)
    echo "💾 Conv ID: $CONV_ID" > /dev/tty
else
    # Reprendre → stdout = dernière réponse
    "$SCRIPT_DIR/../chat.sh" --tools $SCRIPT_DIR/../tools/profiles/refactor.json --resume "$CONV_ID" "$TOOL_OUTPUT" $@
fi

echo "$CONV_ID"
