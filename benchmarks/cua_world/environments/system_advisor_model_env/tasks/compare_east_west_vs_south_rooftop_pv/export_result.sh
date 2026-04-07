#!/bin/bash
echo "=== Exporting task result ==="

# Take final screenshot
DISPLAY=:1 import -window root /tmp/task_end.png 2>/dev/null || \
    DISPLAY=:1 scrot /tmp/task_end.png 2>/dev/null || true

# Record task boundaries
TASK_START=$(cat /home/ga/.task_start_time 2>/dev/null || echo "0")
PYTHON_RAN="false"

# Anti-bypass: Check if Python was actually used during the task
if [ -f /home/ga/.bash_history ]; then
    if grep -q "python3\|python " /home/ga/.bash_history 2>/dev/null; then
        PYTHON_RAN="true"
    fi
fi

# Check if any .py files were created/modified after task start AND contain PySAM imports
PY_FILES=$(find /home/ga -name "*.py" -newer /home/ga/.task_start_time 2>/dev/null)
if [ -n "$PY_FILES" ]; then
    PYSAM_FOUND="false"
    for pyf in $PY_FILES; do
        if grep -ql "import PySAM\|from PySAM\|import Pvwatts\|Pvwattsv" "$pyf" 2>/dev/null; then
            PYSAM_FOUND="true"
            break
        fi
    done
    if [ "$PYSAM_FOUND" = "true" ]; then
        PYTHON_RAN="true"
    fi
fi

# Check if expected file exists
EXPECTED_FILE="/home/ga/Documents/SAM_Projects/rooftop_layout_comparison.json"

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

# Extract parameters from JSON safely using jq
CAP_A="0"
CAP_B="0"
EN_A="0"
EN_B="0"
WINNER=""

if [ -f "$EXPECTED_FILE" ] && command -v jq &> /dev/null; then
    if jq empty "$EXPECTED_FILE" 2>/dev/null; then
        CAP_A=$(jq -r '.capacity_strategy_A_kw // "0"' "$EXPECTED_FILE" 2>/dev/null || echo "0")
        CAP_B=$(jq -r '.capacity_strategy_B_total_kw // "0"' "$EXPECTED_FILE" 2>/dev/null || echo "0")
        EN_A=$(jq -r '.annual_energy_strategy_A_kwh // "0"' "$EXPECTED_FILE" 2>/dev/null || echo "0")
        EN_B=$(jq -r '.annual_energy_strategy_B_total_kwh // "0"' "$EXPECTED_FILE" 2>/dev/null || echo "0")
        WINNER=$(jq -r '.winning_strategy // ""' "$EXPECTED_FILE" 2>/dev/null || echo "")
    fi
fi

# Create JSON result safely using jq into a temporary file
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
jq -n \
    --argjson file_exists "$FILE_EXISTS" \
    --argjson file_size "$FILE_SIZE" \
    --argjson file_modified "$FILE_MODIFIED" \
    --argjson python_ran "$PYTHON_RAN" \
    --arg cap_a "$CAP_A" \
    --arg cap_b "$CAP_B" \
    --arg en_a "$EN_A" \
    --arg en_b "$EN_B" \
    --arg winner "$WINNER" \
    --arg timestamp "$(date -Iseconds)" \
    '{
        file_exists: $file_exists,
        file_size: $file_size,
        file_modified: $file_modified,
        python_ran: $python_ran,
        cap_a: $cap_a,
        cap_b: $cap_b,
        en_a: $en_a,
        en_b: $en_b,
        winner: $winner,
        timestamp: $timestamp
    }' > "$TEMP_JSON"

# Move with permission handling
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="