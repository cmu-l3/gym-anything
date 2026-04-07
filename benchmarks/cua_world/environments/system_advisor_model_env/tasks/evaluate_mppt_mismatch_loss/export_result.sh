#!/bin/bash
echo "=== Exporting task result ==="

# Take final screenshot
DISPLAY=:1 import -window root /tmp/task_final.png 2>/dev/null || true

TASK_START=$(cat /home/ga/.task_start_time 2>/dev/null || echo "0")
PYTHON_RAN="false"

# Check if Python was used
if [ -f /home/ga/.bash_history ]; then
    if grep -q "python3\|python " /home/ga/.bash_history 2>/dev/null; then
        PYTHON_RAN="true"
    fi
fi

# Check for PySAM script
SCRIPT_EXISTS="false"
if [ -f "/home/ga/Documents/SAM_Projects/mismatch_analysis.py" ]; then
    SCRIPT_EXISTS="true"
    if grep -ql "import PySAM\|from PySAM\|Pvsamv1" "/home/ga/Documents/SAM_Projects/mismatch_analysis.py" 2>/dev/null; then
        PYTHON_RAN="true"
    fi
fi

# Check expected JSON
EXPECTED_FILE="/home/ga/Documents/SAM_Projects/mppt_mismatch_results.json"
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

# Extract JSON parameters
SYS_CAP="0"
DUAL_E="0"
SINGLE_E="0"
MISMATCH="0"

if [ "$FILE_EXISTS" = "true" ] && command -v jq &> /dev/null; then
    # Verify JSON is well-formed
    if jq empty "$EXPECTED_FILE" 2>/dev/null; then
        SYS_CAP=$(jq -r '.system_capacity_kw // "0"' "$EXPECTED_FILE" 2>/dev/null || echo "0")
        DUAL_E=$(jq -r '.dual_mppt_annual_energy_kwh // "0"' "$EXPECTED_FILE" 2>/dev/null || echo "0")
        SINGLE_E=$(jq -r '.single_mppt_annual_energy_kwh // "0"' "$EXPECTED_FILE" 2>/dev/null || echo "0")
        MISMATCH=$(jq -r '.mismatch_loss_percentage // "0"' "$EXPECTED_FILE" 2>/dev/null || echo "0")
    fi
fi

jq -n \
    --argjson file_exists "$FILE_EXISTS" \
    --argjson file_size "$FILE_SIZE" \
    --argjson file_modified "$FILE_MODIFIED" \
    --argjson script_exists "$SCRIPT_EXISTS" \
    --argjson python_ran "$PYTHON_RAN" \
    --arg sys_cap "$SYS_CAP" \
    --arg dual_e "$DUAL_E" \
    --arg single_e "$SINGLE_E" \
    --arg mismatch "$MISMATCH" \
    --arg timestamp "$(date -Iseconds)" \
    '{
        file_exists: $file_exists,
        file_size: $file_size,
        file_modified: $file_modified,
        script_exists: $script_exists,
        python_ran: $python_ran,
        system_capacity_kw: $sys_cap,
        dual_energy: $dual_e,
        single_energy: $single_e,
        mismatch_loss_percentage: $mismatch,
        timestamp: $timestamp
    }' > /tmp/task_result.json

chmod 666 /tmp/task_result.json 2>/dev/null || true

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="