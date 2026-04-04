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

# Check if expected files exist
CSV_FILE="/home/ga/Documents/SAM_Projects/Tucson_Hourly_Production.csv"
JSON_FILE="/home/ga/Documents/SAM_Projects/Tucson_Hourly_Summary.json"

CSV_EXISTS="false"
CSV_SIZE=0
CSV_LINES=0
JSON_EXISTS="false"
JSON_SIZE=0
FILE_MODIFIED="false"

if [ -f "$CSV_FILE" ]; then
    CSV_EXISTS="true"
    CSV_SIZE=$(stat -c%s "$CSV_FILE" 2>/dev/null || echo "0")
    # Count data lines (excluding header)
    TOTAL_LINES=$(wc -l < "$CSV_FILE" 2>/dev/null || echo "0")
    CSV_LINES=$((TOTAL_LINES - 1))
    if [ "$CSV_LINES" -lt "0" ]; then
        CSV_LINES=0
    fi

    FILE_MTIME=$(stat -c%Y "$CSV_FILE" 2>/dev/null || echo "0")
    if [ "$FILE_MTIME" -gt "$TASK_START" ]; then
        FILE_MODIFIED="true"
    fi
fi

if [ -f "$JSON_FILE" ]; then
    JSON_EXISTS="true"
    JSON_SIZE=$(stat -c%s "$JSON_FILE" 2>/dev/null || echo "0")
fi

# Extract parameters from JSON summary using flexible key paths
LOCATION_INFO=""
DC_SIZE="0"
ANNUAL_KWH="0"
NUM_HOURS="0"
PEAK_WATTS="0"
HAS_HEADER="false"

if [ -f "$JSON_FILE" ] && command -v jq &> /dev/null; then
    if jq empty "$JSON_FILE" 2>/dev/null; then
        LOCATION_INFO=$(jq -r '
            .location.city //
            .city //
            .location //
            empty
        ' "$JSON_FILE" 2>/dev/null || echo "")

        DC_SIZE=$(jq -r '
            .configuration.system_capacity_kw //
            .system_capacity //
            .configuration.system_capacity //
            .dc_size_kw //
            .system_capacity_kw //
            "0"
        ' "$JSON_FILE" 2>/dev/null || echo "0")

        ANNUAL_KWH=$(jq -r '
            .annual_results.ac_annual_kwh //
            .results.annual_energy //
            .annual_energy_kwh //
            .annual_kwh //
            .ac_annual //
            .total_kwh //
            "0"
        ' "$JSON_FILE" 2>/dev/null || echo "0")

        NUM_HOURS=$(jq -r '
            .num_hours //
            .data_points //
            .num_data_points //
            .hours //
            "0"
        ' "$JSON_FILE" 2>/dev/null || echo "0")

        PEAK_WATTS=$(jq -r '
            .peak_hour_watts //
            .peak_watts //
            .peak_output //
            .peak_power_watts //
            .max_power //
            "0"
        ' "$JSON_FILE" 2>/dev/null || echo "0")

        # If location empty, derive from weather file reference
        if [ -z "$LOCATION_INFO" ] || [ "$LOCATION_INFO" = "-" ] || [ "$LOCATION_INFO" = "null" ]; then
            WF=$(jq -r '.. | select(type=="string") | select(test("tucson"; "i"))' "$JSON_FILE" 2>/dev/null | head -1 || echo "")
            if [ -n "$WF" ]; then
                LOCATION_INFO="tucson"
            fi
        fi
    fi
fi

# Check CSV header - accept various common column names
if [ -f "$CSV_FILE" ]; then
    HEADER=$(head -1 "$CSV_FILE" 2>/dev/null || echo "")
    if echo "$HEADER" | grep -qi "ac_power\|hour\|power\|watt\|output\|generation"; then
        HAS_HEADER="true"
    fi
fi

# Create JSON result safely using jq
jq -n \
    --argjson csv_exists "$CSV_EXISTS" \
    --argjson csv_size "$CSV_SIZE" \
    --argjson csv_lines "$CSV_LINES" \
    --argjson json_exists "$JSON_EXISTS" \
    --argjson json_size "$JSON_SIZE" \
    --argjson file_modified "$FILE_MODIFIED" \
    --argjson python_ran "$PYTHON_RAN" \
    --arg location_info "$LOCATION_INFO" \
    --arg dc_size "$DC_SIZE" \
    --arg annual_kwh "$ANNUAL_KWH" \
    --arg num_hours "$NUM_HOURS" \
    --arg peak_watts "$PEAK_WATTS" \
    --argjson has_header "$HAS_HEADER" \
    --arg timestamp "$(date -Iseconds)" \
    '{
        csv_exists: $csv_exists,
        csv_size: $csv_size,
        csv_lines: $csv_lines,
        json_exists: $json_exists,
        json_size: $json_size,
        file_modified: $file_modified,
        python_ran: $python_ran,
        location_info: $location_info,
        dc_size: $dc_size,
        annual_kwh: $annual_kwh,
        num_hours: $num_hours,
        peak_watts: $peak_watts,
        has_header: $has_header,
        timestamp: $timestamp
    }' > /tmp/task_result.json

chmod 666 /tmp/task_result.json 2>/dev/null || true

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="
