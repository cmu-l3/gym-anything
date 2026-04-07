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
EXPECTED_FILE="/home/ga/Documents/SAM_Projects/winter_optimization_results.json"

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

# Extract parameters using jq
OPTIMAL_TILT="0"
OPTIMAL_AZIMUTH="0"
WINTER_KWH="0"
ANNUAL_KWH="0"

if [ -f "$EXPECTED_FILE" ] && command -v jq &> /dev/null; then
    if jq empty "$EXPECTED_FILE" 2>/dev/null; then
        OPTIMAL_TILT=$(jq -r '
            .optimal_tilt_deg //
            .optimal_tilt //
            "0"
        ' "$EXPECTED_FILE" 2>/dev/null || echo "0")

        OPTIMAL_AZIMUTH=$(jq -r '
            .optimal_azimuth_deg //
            .optimal_azimuth //
            "0"
        ' "$EXPECTED_FILE" 2>/dev/null || echo "0")

        WINTER_KWH=$(jq -r '
            .max_winter_energy_kwh //
            .winter_energy_kwh //
            .max_winter_energy //
            "0"
        ' "$EXPECTED_FILE" 2>/dev/null || echo "0")

        ANNUAL_KWH=$(jq -r '
            .annual_energy_at_optimal_kwh //
            .annual_energy_kwh //
            .annual_energy //
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
    --arg optimal_tilt "$OPTIMAL_TILT" \
    --arg optimal_azimuth "$OPTIMAL_AZIMUTH" \
    --arg winter_kwh "$WINTER_KWH" \
    --arg annual_kwh "$ANNUAL_KWH" \
    --arg timestamp "$(date -Iseconds)" \
    '{
        file_exists: $file_exists,
        file_size: $file_size,
        file_modified: $file_modified,
        python_ran: $python_ran,
        optimal_tilt: $optimal_tilt,
        optimal_azimuth: $optimal_azimuth,
        winter_kwh: $winter_kwh,
        annual_kwh: $annual_kwh,
        timestamp: $timestamp
    }' > /tmp/task_result.json

chmod 666 /tmp/task_result.json 2>/dev/null || true

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="