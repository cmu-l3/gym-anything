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
EXPECTED_FILE="/home/ga/Documents/SAM_Projects/Tucson_Tilt_Analysis.json"

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
LOCATION_INFO=""
OPTIMAL_TILT="0"
OPTIMAL_KWH="0"
NUM_TILTS="0"
HAS_TILT_RESULTS="false"

if [ -f "$EXPECTED_FILE" ] && command -v jq &> /dev/null; then
    if jq empty "$EXPECTED_FILE" 2>/dev/null; then
        LOCATION_INFO=$(jq -r '
            .location.city //
            .city //
            .location //
            empty
        ' "$EXPECTED_FILE" 2>/dev/null || echo "")

        OPTIMAL_TILT=$(jq -r '
            .optimal_tilt_deg //
            .optimal_tilt //
            .best_tilt //
            .optimal_angle //
            "0"
        ' "$EXPECTED_FILE" 2>/dev/null || echo "0")

        OPTIMAL_KWH=$(jq -r '
            .optimal_annual_kwh //
            .max_annual_kwh //
            .optimal_energy //
            .max_energy //
            .best_annual_kwh //
            "0"
        ' "$EXPECTED_FILE" 2>/dev/null || echo "0")

        # Try multiple common names for the tilt results array
        NUM_TILTS=$(jq -r '
            (.tilt_results // .results // .tilt_sweep // .data // []) | length
        ' "$EXPECTED_FILE" 2>/dev/null || echo "0")

        # Check if tilt_results array exists and has data
        TILT_CHECK=$(jq -r '(.tilt_results // .results // .tilt_sweep // .data // null) | type' "$EXPECTED_FILE" 2>/dev/null || echo "")
        if [ "$TILT_CHECK" = "array" ] && [ "$NUM_TILTS" -gt "0" ]; then
            HAS_TILT_RESULTS="true"
        fi

        # If location empty, derive from weather file reference
        if [ -z "$LOCATION_INFO" ] || [ "$LOCATION_INFO" = "-" ] || [ "$LOCATION_INFO" = "null" ]; then
            WF=$(jq -r '.. | select(type=="string") | select(test("tucson"; "i"))' "$EXPECTED_FILE" 2>/dev/null | head -1 || echo "")
            if [ -n "$WF" ]; then
                LOCATION_INFO="tucson"
            fi
        fi
    fi
fi

# Create JSON result safely using jq
jq -n \
    --argjson file_exists "$FILE_EXISTS" \
    --argjson file_size "$FILE_SIZE" \
    --argjson file_modified "$FILE_MODIFIED" \
    --argjson python_ran "$PYTHON_RAN" \
    --arg location_info "$LOCATION_INFO" \
    --arg optimal_tilt "$OPTIMAL_TILT" \
    --arg optimal_kwh "$OPTIMAL_KWH" \
    --arg num_tilts "$NUM_TILTS" \
    --argjson has_tilt_results "$HAS_TILT_RESULTS" \
    --arg timestamp "$(date -Iseconds)" \
    '{
        file_exists: $file_exists,
        file_size: $file_size,
        file_modified: $file_modified,
        python_ran: $python_ran,
        location_info: $location_info,
        optimal_tilt: $optimal_tilt,
        optimal_kwh: $optimal_kwh,
        num_tilts: $num_tilts,
        has_tilt_results: $has_tilt_results,
        timestamp: $timestamp
    }' > /tmp/task_result.json

chmod 666 /tmp/task_result.json 2>/dev/null || true

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="
