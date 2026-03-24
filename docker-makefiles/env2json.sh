#!/usr/bin/env bash

#!/usr/bin/env bash
# =============================================================================
# env_to_json.sh
#
# Converts a .env file into a JSON file.
# Comments (#) and blank lines are skipped.
# Values are type-cast to match the schema used in service_definition.json:
#   - "true" / "false"  → JSON boolean
#   - pure integers      → JSON number
#   - everything else    → JSON string  (surrounding quotes stripped first)
#
# Handles both Unix (LF) and Windows (CRLF) line endings.
#
# Usage:
#   ./env_to_json.sh [INPUT_ENV] [OUTPUT_JSON]
#
# Defaults (if args are omitted):
#   INPUT_ENV   = node_configs.env
#   OUTPUT_JSON = node_configs.json
# =============================================================================

set -euo pipefail

INPUT_DIR=${1:-anylog-generic}
SAMPLE_FILE=${2:-../service.definition.json}

if [[ ! -d "${INPUT_DIR}" ]]; then
    echo "Unable to find directory ${INPUT_DIR}" >&2
    exit 1
elif [[ ! -f "${INPUT_DIR}/node_configs.env" ]]; then
    echo "Unable to find config file: ${INPUT_DIR}/node_configs.env" >&2
    exit 1
else
    INPUT_ENV="${INPUT_DIR}/node_configs.env"
    OUTPUT_JSON="${INPUT_DIR}/service.definition.json"
fi

if [[ ! -f ${SAMPLE_FILE} ]] ; then
  echo "Missing base config file: ${SAMPLE_FILE}"
  exit 1
else
  cp ${SAMPLE_FILE} ${INPUT_DIR}
fi


# --------------------------------------------------------------------------- #
# Validation
# --------------------------------------------------------------------------- #
if [[ ! -f "$INPUT_ENV" ]]; then
    echo "ERROR: Input file '$INPUT_ENV' not found." >&2
    exit 1
fi

# --------------------------------------------------------------------------- #
# Helper – strip surrounding double-quotes from a raw value
#   ""        → (empty string)
#   "hello"   → hello
#   hello     → hello   (no-op when no surrounding quotes)
# --------------------------------------------------------------------------- #
strip_quotes() {
    local v="$1"
    if [[ ${#v} -ge 2 && "${v:0:1}" == '"' && "${v: -1}" == '"' ]]; then
        v="${v:1:${#v}-2}"
    fi
    printf '%s' "$v"
}

# --------------------------------------------------------------------------- #
# Helper – emit a properly typed JSON value
# --------------------------------------------------------------------------- #
json_value() {
    local raw
    raw="$(strip_quotes "$1")"

    # Boolean
    if [[ "$raw" == "true" || "$raw" == "false" ]]; then
        printf '%s' "$raw"
        return
    fi

    # Integer (optional leading minus, digits only)
    if [[ "$raw" =~ ^-?[0-9]+$ ]]; then
        printf '%s' "$raw"
        return
    fi

    # String – escape backslash, double-quote, tab, newline
    local escaped
    escaped=$(printf '%s' "$raw" \
        | sed 's/\\/\\\\/g'  \
        | sed 's/"/\\"/g'    \
        | sed $'s/\t/\\\\t/g' \
        | sed ':a;N;$!ba;s/\n/\\n/g')
    printf '"%s"' "$escaped"
}

# --------------------------------------------------------------------------- #
# Parse .env → JSON
# --------------------------------------------------------------------------- #
{
    echo "{"

    first=true
    while IFS= read -r line || [[ -n "$line" ]]; do

        # Strip Windows carriage return (\r) if present
        line="${line%$'\r'}"

        # Skip blank lines and comment-only lines
        [[ -z "$line" || "$line" =~ ^[[:space:]]*# ]] && continue

        # Must contain '='
        [[ "$line" != *=* ]] && continue

        key="${line%%=*}"
        value="${line#*=}"

        # Skip keys that are empty or contain spaces (malformed lines)
        [[ -z "$key" || "$key" =~ [[:space:]] ]] && continue

        # Strip inline comment only when preceded by whitespace
        # (avoids breaking URLs like https://example.com/#anchor)
        value=$(printf '%s' "$value" | sed 's/[[:space:]]\{1,\}#[^"]*$//')

        # Comma separator between entries
        if [[ "$first" == true ]]; then
            first=false
        else
            printf ',\n'
        fi

        printf '  "%s": %s' "$key" "$(json_value "$value")"

    done < "$INPUT_ENV"

    printf '\n}\n'

} > "$OUTPUT_JSON"

echo "✓  Converted '$INPUT_ENV'  →  '$OUTPUT_JSON'"