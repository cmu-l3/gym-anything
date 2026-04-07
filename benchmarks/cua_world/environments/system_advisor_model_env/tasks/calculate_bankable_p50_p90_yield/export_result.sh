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
EXPECTED_FILE="/home/ga/Documents/SAM_Projects/p50_p90_yield_report.json"

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
P50_ENERGY="0"
TOTAL_UNCERTAINTY="0"
P75_ENERGY="0"
P90_ENERGY="0"
P99_ENERGY="0"

if [ -f "$EXPECTED_FILE" ] && command -v jq &> /dev/null; then
    if jq empty "$EXPECTED_FILE" 2>/dev/null; then
        SYSTEM_CAPACITY=$(jq -r '
            .system_capacity_kw //
            .capacity_kw //
            .system_capacity //
            "0"
        ' "$EXPECTED_FILE" 2>/dev/null || echo "0")

        P50_ENERGY=$(jq -r '
            .p50_energy_kwh //
            .p50_kwh //
            .annual_energy_kwh //
            .p50_energy //
            "0"
        ' "$EXPECTED_FILE" 2>/dev/null || echo "0")

        TOTAL_UNCERTAINTY=$(jq -r '
            .total_uncertainty_percent //
            .total_uncertainty_pct //
            .uncertainty_percent //
            .total_uncertainty //
            "0"
        ' "$EXPECTED_FILE" 2>/dev/null || echo "0")

        P75_ENERGY=$(jq -r '
            .p75_energy_kwh //
            .p75_kwh //
            .p75_energy //
            "0"
        ' "$EXPECTED_FILE" 2>/dev/null || echo "0")

        P90_ENERGY=$(jq -r '
            .p90_energy_kwh //
            .p90_kwh //
            .p90_energy //
            "0"
        ' "$EXPECTED_FILE" 2>/dev/null || echo "0")

        P99_ENERGY=$(jq -r '
            .p99_energy_kwh //
            .p99_kwh //
            .p99_energy //
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
    --arg p50_energy "$P50_ENERGY" \
    --arg total_uncertainty "$TOTAL_UNCERTAINTY" \
    --arg p75_energy "$P75_ENERGY" \
    --arg p90_energy "$P90_ENERGY" \
    --arg p99_energy "$P99_ENERGY" \
    --arg timestamp "$(date -Iseconds)" \
    '{
        file_exists: $file_exists,
        file_size: $file_size,
        file_modified: $file_modified,
        python_ran: $python_ran,
        system_capacity: $system_capacity,
        p50_energy: $p50_energy,
        total_uncertainty: $total_uncertainty,
        p75_energy: $p75_energy,
        p90_energy: $p90_energy,
        p99_energy: $p99_energy,
        timestamp: $timestamp
    }' > /tmp/task_result.json

chmod 666 /tmp/task_result.json 2>/dev/null || true

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="