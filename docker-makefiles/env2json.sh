#!/usr/bin/env bash
# =============================================================================
# env_to_json.sh
#
# Converts a .env file into a JSON file, mirroring the Python implementation.
# Reads node_configs.env, pairs each KEY=VALUE with its preceding comment
# block, type-casts values, and injects the result into the `userInput` field
# of a copied service.definition.json.
#
# Type casting rules (mirrors ast.literal_eval):
#   - Pure integer or float  → JSON number,  type "int"
#   - Everything else        → JSON string,  type "string"
#   - true/false stay as     → type "string" (Python needs True/False)
#
# Requires: jq
#
# Usage:
#   ./env_to_json.sh [INPUT_DIR] [SAMPLE_FILE]
#
# Defaults:
#   INPUT_DIR   = anylog-generic
#   SAMPLE_FILE = ../service.definition.json
#
# Output: INPUT_DIR/node_configs.json
# =============================================================================

set -euo pipefail

INPUT_DIR="${1:-anylog-generic}"
SAMPLE_FILE="${2:-../service.definition.json}"

# --------------------------------------------------------------------------- #
# Validation
# --------------------------------------------------------------------------- #
if [[ ! -d "${INPUT_DIR}" ]]; then
    echo "Unable to find directory ${INPUT_DIR}" >&2
    exit 1
elif [[ ! -f "${INPUT_DIR}/node_configs.env" ]]; then
    echo "Unable to find config file: ${INPUT_DIR}/node_configs.env" >&2
    exit 1
fi

if [[ ! -f "${SAMPLE_FILE}" ]]; then
    echo "Missing base config file: ${SAMPLE_FILE}" >&2
    exit 1
fi

if ! command -v jq &>/dev/null; then
    echo "ERROR: jq is required but not installed." >&2
    exit 1
fi

INPUT_ENV="${INPUT_DIR}/node_configs.env"
OUTPUT_JSON="${INPUT_DIR}/node_configs.json"

# Copy the sample service definition — userInput will be replaced below
cp "${SAMPLE_FILE}" "${OUTPUT_JSON}"

# --------------------------------------------------------------------------- #
# Helper – emit one userInput entry into the accumulator file
#
# Arguments:
#   $1  param      – KEY name
#   $2  comment    – accumulated comment string (# chars already stripped,
#                    lines joined — mirrors comment.replace('#','').replace('\n',' ').strip())
#   $3  raw_value  – raw value string from the .env line
#   $4  accum_file – path to the JSON array accumulator file
# --------------------------------------------------------------------------- #
emit_entry() {
    local param="$1"
    local comment="$2"
    local raw_value="$3"
    local accum_file="$4"

    # --- Clean value: strip surrounding double-quotes, then trim whitespace ---
    local value="$raw_value"
    if [[ ${#value} -ge 2 && "${value:0:1}" == '"' && "${value: -1}" == '"' ]]; then
        value="${value:1:${#value}-2}"
    fi
    value="$(printf '%s' "$value" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"

    # --- Build label: remove '#' chars, trim leading/trailing whitespace ------
    # comment lines were already stripped individually; we just clean '#' and
    # trim the final result (mirrors .replace('#','').replace('\n',' ').strip())
    local label
    label="$(printf '%s' "$comment" | sed 's/#//g' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"

    # --- Type-cast (mirrors ast.literal_eval) ---------------------------------
    local vtype="string"
    if [[ "$value" =~ ^-?[0-9]+$ ]] || [[ "$value" =~ ^-?[0-9]*\.[0-9]+$ ]]; then
        vtype="int"
    fi

    # --- Append to the JSON array using jq ------------------------------------
    local tmp
    tmp="$(mktemp)"

    if [[ "$vtype" == "int" ]]; then
        jq --arg  name  "$param"  \
           --arg  label "$label"  \
           --arg  type  "$vtype"  \
           --argjson value "$value" \
           '. += [{"name": $name, "label": $label, "type": $type, "value": $value}]' \
           "$accum_file" > "$tmp"
    else
        jq --arg name  "$param"  \
           --arg label "$label"  \
           --arg type  "$vtype"  \
           --arg value "$value"  \
           '. += [{"name": $name, "label": $label, "type": $type, "value": $value}]' \
           "$accum_file" > "$tmp"
    fi

    mv "$tmp" "$accum_file"
}

# --------------------------------------------------------------------------- #
# Parse .env → build userInput array
# --------------------------------------------------------------------------- #
ACCUM="$(mktemp)"
echo "[]" > "$ACCUM"

comment=""
param=""
value=""

while IFS= read -r line || [[ -n "$line" ]]; do

    # Strip Windows carriage return (\r) if present
    line="${line%$'\r'}"

    # Process non-empty lines only (mirrors `if line.strip():`)
    if [[ -n "${line// /}" ]]; then
        if [[ "$line" == \#===* || "$line" == \#---* ]]; then
            : # section headers / sub-headers — skip entirely
        elif [[ "$line" == \#* ]]; then
            # strip each comment line before accumulating (mirrors line.strip())
            local_stripped="$(printf '%s' "$line" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"
            comment+="${local_stripped}"
        elif [[ "$line" == *=* ]]; then
            param="${line%%=*}"
            value="${line#*=}"
        fi
    fi

    # Emit when all three accumulators are populated
    # (mirrors the unconditional `if comment and param and value:` check)
    if [[ -n "$comment" && -n "$param" && -n "$value" ]]; then
        emit_entry "$param" "$comment" "$value" "$ACCUM"
        comment=""
        param=""
        value=""
    fi

done < "$INPUT_ENV"

# --------------------------------------------------------------------------- #
# Inject the userInput array into the output JSON
# --------------------------------------------------------------------------- #
user_input_json="$(cat "$ACCUM")"
tmp_out="$(mktemp)"
jq --argjson ui "$user_input_json" '.userInput = $ui' "$OUTPUT_JSON" > "$tmp_out"
mv "$tmp_out" "$OUTPUT_JSON"
rm -f "$ACCUM"

echo "✓  Converted '${INPUT_ENV}'  →  '${OUTPUT_JSON}'"