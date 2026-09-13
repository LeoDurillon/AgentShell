#!/usr/bin/env bash

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FILE="$1"

[[ -f "$FILE" ]] || exit 1

SIGNALS=()

add_signal() {
    local severity="$1"
    local message="$2"

    SIGNALS+=("- ${severity} ${message}")
}

query_count() {
    local rule="$1"
    local count

    count=$(
        ast-grep scan \
            --rule "$SCRIPT_DIR/$rule.yml" \
            --json "$FILE" 2>/dev/null |
        jq 'length' 2>/dev/null
    )

    echo "${count:-0}"
}


collect_ts_metrics() {
    any_count=$(query_count typescript/any)
    type_assertion=$(query_count typescript/type-assertion)
    non_null=$(query_count typescript/non-null)
    ts_ignore=$(query_count typescript/ts-ignore)
}

collect_react_metrics() {
    use_state=$(query_count react/use-state)
    use_effect=$(query_count react/use-effect)
    use_memo=$(query_count react/use-memo)
    use_callback=$(query_count react/use-callback)
    use_context=$(query_count react/use-context)
    jsx_elements=$(query_count react/jsx-element)
    conditional_rendering=$(query_count react/conditional-rendering)
    fragments=$(query_count react/fragments)
}

collect_next_metrics() {
    fetch_count=$(query_count next/fetch)
    router_count=$(query_count next/router)
    metadata_count=$(query_count next/metadata)

    client="No"

    grep -qE "^['\"]use client['\"]" "$FILE" &&
        client="Yes"
}


generate_signals() {

    if (( any_count >= 5 )); then
        add_signal "🔴" "Heavy use of explicit any (${any_count})"
    elif (( any_count > 0 )); then
        add_signal "🟡" "Uses explicit any (${any_count})"
    fi

    if (( ts_ignore >= 3 )); then
        add_signal "🔴" "Multiple @ts-ignore directives (${ts_ignore})"
    elif (( ts_ignore > 0 )); then
        add_signal "🟡" "Uses @ts-ignore (${ts_ignore})"
    fi

    if (( type_assertion >= 15 )); then
        add_signal "🔴" "Heavy use of type assertions (${type_assertion})"
    elif (( type_assertion >= 5 )); then
        add_signal "🟡" "Frequent type assertions (${type_assertion})"
    fi

    if (( non_null >= 8 )); then
        add_signal "🔴" "Heavy use of non-null assertions (${non_null})"
    elif (( non_null >= 3 )); then
        add_signal "🟡" "Several non-null assertions (${non_null})"
    fi

    if (( use_state >= 8 )); then
        add_signal "🔴" "Very high state usage (${use_state} useState)"
    elif (( use_state >= 5 )); then
        add_signal "🟡" "High state usage (${use_state} useState)"
    fi

    if (( use_effect >= 5 )); then
        add_signal "🔴" "Many useEffect hooks (${use_effect})"
    elif (( use_effect >= 3 )); then
        add_signal "🟡" "Multiple useEffect hooks (${use_effect})"
    fi

    if (( use_memo >= 8 )); then
        add_signal "🔴" "Heavy use of useMemo (${use_memo})"
    elif (( use_memo >= 4 )); then
        add_signal "🟡" "Many memoized values (${use_memo})"
    fi

    if (( use_callback >= 10 )); then
        add_signal "🔴" "Heavy use of useCallback (${use_callback})"
    elif (( use_callback >= 5 )); then
        add_signal "🟡" "Many callbacks (${use_callback})"
    fi

    if (( use_context >= 6 )); then
        add_signal "🔴" "Many contexts used (${use_context})"
    elif (( use_context >= 3 )); then
        add_signal "🟡" "Several contexts used (${use_context})"
    fi

    if (( jsx_elements >= 120 )); then
        add_signal "🔴" "Very large JSX tree (${jsx_elements} elements)"
    elif (( jsx_elements >= 60 )); then
        add_signal "🟡" "Large JSX tree (${jsx_elements} elements)"
    fi

    if (( conditional_rendering >= 10 )); then
        add_signal "🔴" "Complex conditional rendering (${conditional_rendering})"
    elif (( conditional_rendering >= 5 )); then
        add_signal "🟡" "Many conditional render blocks (${conditional_rendering})"
    fi

    if (( fragments >= 8 )); then
        add_signal "🔴" "Many JSX fragments (${fragments})"
    elif (( fragments >= 4 )); then
        add_signal "🟡" "Several JSX fragments (${fragments})"
    fi

    if (( fetch_count >= 5 )); then
        add_signal "🔴" "Many fetch() calls (${fetch_count})"
    elif (( fetch_count >= 2 )); then
        add_signal "🟡" "Multiple fetch() calls (${fetch_count})"
    fi

    if (( router_count >= 4 )); then
        add_signal "🔴" "Many useRouter() usages (${router_count})"
    elif (( router_count >= 2 )); then
        add_signal "🟡" "Multiple useRouter() usages (${router_count})"
    fi

    [[ "$client" == "Yes" ]] &&
        add_signal "ℹ️" "Client component"
}


print_signals() {
    echo "## Framework Signals"
    echo

    if ((${#SIGNALS[@]} == 0)); then
        echo "✅ No notable framework signals detected."
    else
        printf "%s\n" "${SIGNALS[@]}"
    fi
}

print_ts_table() {
    echo "### TypeScript"
    echo
    echo "| Metric | Count |"
    echo "|--------|------:|"
    echo "| explicit any | $any_count |"
    echo "| type assertions | $type_assertion |"
    echo "| non-null assertions | $non_null |"
    echo "| @ts-ignore | $ts_ignore |"
}

print_react_table() {
    echo
    echo "### React"
    echo
    echo "| Metric | Count |"
    echo "|--------|------:|"
    echo "| useState | $use_state |"
    echo "| useEffect | $use_effect |"
    echo "| useMemo | $use_memo |"
    echo "| useCallback | $use_callback |"
    echo "| useContext | $use_context |"
    echo "| JSX elements | $jsx_elements |"
    echo "| Conditional rendering | $conditional_rendering |"
    echo "| JSX fragments | $fragments |"
}

print_next_table() {
    echo
    echo "### Next.js"
    echo
    echo "| Metric | Count |"
    echo "|--------|------:|"
    echo "| fetch() | $fetch_count |"
    echo "| useRouter() | $router_count |"
    echo "| metadata export | $metadata_count |"
    echo "| Client component | $client |"
}


echo "## Framework Analysis"
echo

collect_ts_metrics

case "${FILE##*.}" in
    tsx|jsx)
        collect_react_metrics
        collect_next_metrics
        ;;
esac

generate_signals
print_signals

echo
print_ts_table

case "${FILE##*.}" in
    tsx|jsx)
        print_react_table
        print_next_table
        ;;
esac
