#!/bin/bash
echo "=== Exporting task result ==="

# Take final screenshot
DISPLAY=:1 import -window root /tmp/task_end.png 2>/dev/null || \
    DISPLAY=:1 scrot /tmp/task_end.png 2>/dev/null || true

# Anti-bypass: Check if Python or SAM GUI was actually used
TASK_START=$(cat /home/ga/.task_start_time 2>/dev/null || echo "0")
PYTHON_RAN="false"
SAM_GUI_USED="false"

# Check bash history for python3 commands
if [ -f /home/ga/.bash_history ]; then
    if grep -q "python3\|python " /home/ga/.bash_history 2>/dev/null; then
        PYTHON_RAN="true"
    fi
fi

# Check if any .py files were created/modified after task start
PY_FILES=$(find /home/ga -name "*.py" -newer /home/ga/.task_start_time 2>/dev/null)
if [ -n "$PY_FILES" ]; then
    PYSAM_FOUND="false"
    for pyf in $PY_FILES; do
        if grep -ql "import PySAM\|from PySAM" "$pyf" 2>/dev/null; then
            PYSAM_FOUND="true"
            break
        fi
    done
    if [ "$PYSAM_FOUND" = "true" ]; then
        PYTHON_RAN="true"
    fi
fi

# Check if .sam file was created/modified after task start
SAM_FILES=$(find /home/ga -name "*.sam" -newer /home/ga/.task_start_time 2>/dev/null)
if [ -n "$SAM_FILES" ]; then
    SAM_GUI_USED="true"
fi

# Check if expected JSON results file exists
EXPECTED_FILE="/home/ga/Documents/SAM_Projects/peak_shaving_results.json"

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

# Extract parameters from JSON result file using jq
BATTERY_POWER="0"
BATTERY_ENERGY="0"
ORIGINAL_PEAK="0"
NEW_PEAK="0"
PEAK_REDUCTION="0"
ANNUAL_LOAD="0"

if [ -f "$EXPECTED_FILE" ] && command -v jq &> /dev/null; then
    if jq empty "$EXPECTED_FILE" 2>/dev/null; then
        BATTERY_POWER=$(jq -r '
            .battery_power_kw //
            "0"
        ' "$EXPECTED_FILE" 2>/dev/null || echo "0")

        BATTERY_ENERGY=$(jq -r '
            .battery_energy_kwh //
            "0"
        ' "$EXPECTED_FILE" 2>/dev/null || echo "0")

        ORIGINAL_PEAK=$(jq -r '
            .original_peak_demand_kw //
            "0"
        ' "$EXPECTED_FILE" 2>/dev/null || echo "0")

        NEW_PEAK=$(jq -r '
            .new_peak_demand_kw //
            "0"
        ' "$EXPECTED_FILE" 2>/dev/null || echo "0")

        PEAK_REDUCTION=$(jq -r '
            .peak_reduction_kw //
            "0"
        ' "$EXPECTED_FILE" 2>/dev/null || echo "0")
        
        ANNUAL_LOAD=$(jq -r '
            .annual_load_kwh //
            "0"
        ' "$EXPECTED_FILE" 2>/dev/null || echo "0")
    fi
fi

# Create JSON result safely using jq
jq -n \
    --argjson file_exists "$FILE_EXISTS" \
    --argjson file_size "$FILE_SIZE" \
    --argjson file_modified "$FILE_MODIFIED" \
    --argjson python_ran "$PYTHON_RAN" \
    --argjson sam_gui_used "$SAM_GUI_USED" \
    --arg battery_power "$BATTERY_POWER" \
    --arg battery_energy "$BATTERY_ENERGY" \
    --arg original_peak "$ORIGINAL_PEAK" \
    --arg new_peak "$NEW_PEAK" \
    --arg peak_reduction "$PEAK_REDUCTION" \
    --arg annual_load "$ANNUAL_LOAD" \
    --arg timestamp "$(date -Iseconds)" \
    '{
        file_exists: $file_exists,
        file_size: $file_size,
        file_modified: $file_modified,
        python_ran: $python_ran,
        sam_gui_used: $sam_gui_used,
        battery_power: $battery_power,
        battery_energy: $battery_energy,
        original_peak: $original_peak,
        new_peak: $new_peak,
        peak_reduction: $peak_reduction,
        annual_load: $annual_load,
        timestamp: $timestamp
    }' > /tmp/task_result.json

chmod 666 /tmp/task_result.json 2>/dev/null || true

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="