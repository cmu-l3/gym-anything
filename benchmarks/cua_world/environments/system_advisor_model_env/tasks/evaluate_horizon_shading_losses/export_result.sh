#!/bin/bash
echo "=== Exporting task result ==="

# Take final screenshot
DISPLAY=:1 import -window root /tmp/task_end.png 2>/dev/null || true

# Anti-bypass: Check if Python was actually used during the task
TASK_START=$(cat /home/ga/.task_start_time 2>/dev/null || echo "0")
PYTHON_RAN="false"

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
EXPECTED_FILE="/home/ga/Documents/SAM_Projects/horizon_shading_impact.json"

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

# Extract parameters using flexible key paths
SYSTEM_CAPACITY="0"
WEATHER_FILE=""
BASELINE_ENERGY="0"
SHADED_ENERGY="0"
ENERGY_LOSS_PERCENT="0"

if [ -f "$EXPECTED_FILE" ] && command -v jq &> /dev/null; then
    if jq empty "$EXPECTED_FILE" 2>/dev/null; then
        SYSTEM_CAPACITY=$(jq -r '
            .system_capacity_kw //
            .system_capacity //
            "0"
        ' "$EXPECTED_FILE" 2>/dev/null || echo "0")

        WEATHER_FILE=$(jq -r '
            .weather_file //
            .weather //
            empty
        ' "$EXPECTED_FILE" 2>/dev/null || echo "")

        BASELINE_ENERGY=$(jq -r '
            .baseline_annual_energy_kwh //
            .baseline_annual_energy //
            .baseline_energy //
            "0"
        ' "$EXPECTED_FILE" 2>/dev/null || echo "0")
        
        SHADED_ENERGY=$(jq -r '
            .shaded_annual_energy_kwh //
            .shaded_annual_energy //
            .shaded_energy //
            "0"
        ' "$EXPECTED_FILE" 2>/dev/null || echo "0")
        
        ENERGY_LOSS_PERCENT=$(jq -r '
            .energy_loss_percent //
            .loss_percent //
            .percent_loss //
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
    --arg system_capacity "$SYSTEM_CAPACITY" \
    --arg weather_file "$WEATHER_FILE" \
    --arg baseline_energy "$BASELINE_ENERGY" \
    --arg shaded_energy "$SHADED_ENERGY" \
    --arg energy_loss_percent "$ENERGY_LOSS_PERCENT" \
    --arg timestamp "$(date -Iseconds)" \
    '{
        file_exists: $file_exists,
        file_size: $file_size,
        file_modified: $file_modified,
        python_ran: $python_ran,
        system_capacity: $system_capacity,
        weather_file: $weather_file,
        baseline_energy: $baseline_energy,
        shaded_energy: $shaded_energy,
        energy_loss_percent: $energy_loss_percent,
        timestamp: $timestamp
    }' > /tmp/task_result.json

chmod 666 /tmp/task_result.json 2>/dev/null || true

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="