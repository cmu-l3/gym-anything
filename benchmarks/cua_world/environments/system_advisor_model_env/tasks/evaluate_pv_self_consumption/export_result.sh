#!/bin/bash
echo "=== Exporting task result ==="

# Take final screenshot
DISPLAY=:1 import -window root /tmp/task_end.png 2>/dev/null || true

# Anti-bypass: Check if Python was actually used during the task
TASK_START=$(cat /home/ga/.task_start_time 2>/dev/null || echo "0")
PYTHON_RAN="false"
PYSAM_FOUND="false"
SCRIPT_PATH=""

if [ -f /home/ga/.bash_history ]; then
    if grep -q "python3\|python " /home/ga/.bash_history 2>/dev/null; then
        PYTHON_RAN="true"
    fi
fi

# Check if any .py files were created/modified after task start AND contain PySAM imports
PY_FILES=$(find /home/ga -name "*.py" -newer /home/ga/.task_start_time 2>/dev/null)
if [ -n "$PY_FILES" ]; then
    for pyf in $PY_FILES; do
        if grep -ql "import PySAM\|from PySAM\|import Pvwatts\|Pvwattsv" "$pyf" 2>/dev/null; then
            PYSAM_FOUND="true"
            PYTHON_RAN="true"
            SCRIPT_PATH="$pyf"
            break
        fi
    done
fi

# Check if expected file exists
EXPECTED_FILE="/home/ga/Documents/SAM_Projects/self_consumption_results.json"
EXPECTED_LOAD=$(cat /home/ga/.expected_load.txt 2>/dev/null || echo "0")

FILE_EXISTS="false"
FILE_SIZE=0
FILE_MODIFIED="false"

if [ -f "$EXPECTED_FILE" ]; then
    FILE_EXISTS="true"
    FILE_SIZE=$(stat -c%s "$EXPECTED_FILE" 2>/dev/null || echo "0")

    FILE_MTIME=$(stat -c%Y "$EXPECTED_FILE" 2>/dev/null || echo "0")
    if [ "$FILE_MTIME" -gt "$TASK_START" ]; then
        FILE_MODIFIED="true"
    fi
fi

# Extract JSON parameters safely
ANNUAL_ENERGY="0"
ANNUAL_LOAD="0"
ANNUAL_EXPORTED="0"
ANNUAL_IMPORTED="0"
SELF_CONS_PCT="0"
SOLAR_FRAC_PCT="0"
JSON_KEYS_VALID="false"

if [ -f "$EXPECTED_FILE" ] && command -v jq &> /dev/null; then
    if jq empty "$EXPECTED_FILE" 2>/dev/null; then
        ANNUAL_ENERGY=$(jq -r '.annual_energy_kwh // 0' "$EXPECTED_FILE" 2>/dev/null)
        ANNUAL_LOAD=$(jq -r '.annual_load_kwh // 0' "$EXPECTED_FILE" 2>/dev/null)
        ANNUAL_EXPORTED=$(jq -r '.annual_energy_exported_kwh // 0' "$EXPECTED_FILE" 2>/dev/null)
        ANNUAL_IMPORTED=$(jq -r '.annual_energy_imported_kwh // 0' "$EXPECTED_FILE" 2>/dev/null)
        SELF_CONS_PCT=$(jq -r '.self_consumption_ratio_pct // 0' "$EXPECTED_FILE" 2>/dev/null)
        SOLAR_FRAC_PCT=$(jq -r '.solar_fraction_pct // 0' "$EXPECTED_FILE" 2>/dev/null)
        
        # Check if all keys exist
        KEY_COUNT=$(jq 'keys | contains(["annual_energy_exported_kwh", "annual_energy_imported_kwh", "annual_energy_kwh", "annual_load_kwh", "self_consumption_ratio_pct", "solar_fraction_pct"])' "$EXPECTED_FILE" 2>/dev/null)
        if [ "$KEY_COUNT" = "true" ]; then
            JSON_KEYS_VALID="true"
        fi
    fi
fi

# Copy the agent's script to a known location for the verifier
if [ -n "$SCRIPT_PATH" ] && [ -f "$SCRIPT_PATH" ]; then
    cp "$SCRIPT_PATH" /tmp/agent_script.py
else
    touch /tmp/agent_script.py
fi

# Create JSON result safely using jq
jq -n \
    --argjson file_exists "$FILE_EXISTS" \
    --argjson file_size "$FILE_SIZE" \
    --argjson file_modified "$FILE_MODIFIED" \
    --argjson python_ran "$PYTHON_RAN" \
    --argjson json_keys_valid "$JSON_KEYS_VALID" \
    --arg annual_energy "$ANNUAL_ENERGY" \
    --arg annual_load "$ANNUAL_LOAD" \
    --arg annual_exported "$ANNUAL_EXPORTED" \
    --arg annual_imported "$ANNUAL_IMPORTED" \
    --arg self_cons_pct "$SELF_CONS_PCT" \
    --arg solar_frac_pct "$SOLAR_FRAC_PCT" \
    --arg expected_load "$EXPECTED_LOAD" \
    --arg timestamp "$(date -Iseconds)" \
    '{
        file_exists: $file_exists,
        file_size: $file_size,
        file_modified: $file_modified,
        python_ran: $python_ran,
        json_keys_valid: $json_keys_valid,
        annual_energy: $annual_energy,
        annual_load: $annual_load,
        annual_exported: $annual_exported,
        annual_imported: $annual_imported,
        self_cons_pct: $self_cons_pct,
        solar_frac_pct: $solar_frac_pct,
        expected_load: $expected_load,
        timestamp: $timestamp
    }' > /tmp/task_result.json

chmod 666 /tmp/task_result.json 2>/dev/null || true
chmod 666 /tmp/agent_script.py 2>/dev/null || true

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="