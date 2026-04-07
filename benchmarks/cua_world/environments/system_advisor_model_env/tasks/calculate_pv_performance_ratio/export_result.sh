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
EXPECTED_FILE="/home/ga/Documents/SAM_Projects/pr_calculation_report.json"

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
ANNUAL_ENERGY="0"
ANNUAL_INSOLATION="0"
PERFORMANCE_RATIO="0"
WEATHER_FILE=""

if [ -f "$EXPECTED_FILE" ] && command -v jq &> /dev/null; then
    if jq empty "$EXPECTED_FILE" 2>/dev/null; then
        SYSTEM_CAPACITY=$(jq -r '
            .system_capacity_kw //
            .system_capacity //
            .capacity_kw //
            "0"
        ' "$EXPECTED_FILE" 2>/dev/null || echo "0")

        ANNUAL_ENERGY=$(jq -r '
            .annual_energy_kwh //
            .annual_energy //
            .energy_kwh //
            "0"
        ' "$EXPECTED_FILE" 2>/dev/null || echo "0")

        ANNUAL_INSOLATION=$(jq -r '
            .annual_poa_insolation_kwh_m2 //
            .annual_insolation_kwh_m2 //
            .annual_poa_insolation //
            .insolation_kwh_m2 //
            "0"
        ' "$EXPECTED_FILE" 2>/dev/null || echo "0")

        PERFORMANCE_RATIO=$(jq -r '
            .performance_ratio //
            .pr //
            "0"
        ' "$EXPECTED_FILE" 2>/dev/null || echo "0")

        WEATHER_FILE=$(jq -r '
            .weather_file_used //
            .weather_file //
            ""
        ' "$EXPECTED_FILE" 2>/dev/null || echo "")
    fi
fi

# Create JSON result safely using jq
jq -n \
    --argjson file_exists "$FILE_EXISTS" \
    --argjson file_size "$FILE_SIZE" \
    --argjson file_modified "$FILE_MODIFIED" \
    --argjson python_ran "$PYTHON_RAN" \
    --arg system_capacity "$SYSTEM_CAPACITY" \
    --arg annual_energy "$ANNUAL_ENERGY" \
    --arg annual_insolation "$ANNUAL_INSOLATION" \
    --arg performance_ratio "$PERFORMANCE_RATIO" \
    --arg weather_file "$WEATHER_FILE" \
    --arg timestamp "$(date -Iseconds)" \
    '{
        file_exists: $file_exists,
        file_size: $file_size,
        file_modified: $file_modified,
        python_ran: $python_ran,
        system_capacity: $system_capacity,
        annual_energy: $annual_energy,
        annual_insolation: $annual_insolation,
        performance_ratio: $performance_ratio,
        weather_file: $weather_file,
        timestamp: $timestamp
    }' > /tmp/task_result.json

chmod 666 /tmp/task_result.json 2>/dev/null || true

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="