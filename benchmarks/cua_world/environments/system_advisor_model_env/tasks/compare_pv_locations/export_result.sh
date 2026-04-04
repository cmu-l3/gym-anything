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
EXPECTED_FILE="/home/ga/Documents/SAM_Projects/PV_Location_Comparison.json"

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
NUM_LOCATIONS="0"
BEST_LOCATION=""
WORST_LOCATION=""
PHOENIX_KWH="0"
TUCSON_KWH="0"
DES_MOINES_KWH="0"
HAS_COMPARISON="false"

if [ -f "$EXPECTED_FILE" ] && command -v jq &> /dev/null; then
    if jq empty "$EXPECTED_FILE" 2>/dev/null; then
        # Try multiple common names for the comparison array
        COMP_ARRAY_NAME=$(jq -r 'keys[] | select(test("comparison|results|locations|cities|data"; "i"))' "$EXPECTED_FILE" 2>/dev/null | head -1 || echo "comparison")
        if [ -z "$COMP_ARRAY_NAME" ]; then
            COMP_ARRAY_NAME="comparison"
        fi

        NUM_LOCATIONS=$(jq -r "(.${COMP_ARRAY_NAME} // []) | length" "$EXPECTED_FILE" 2>/dev/null || echo "0")

        BEST_LOCATION=$(jq -r '
            .best_location //
            .best_city //
            .best //
            .highest_production //
            ""
        ' "$EXPECTED_FILE" 2>/dev/null || echo "")

        WORST_LOCATION=$(jq -r '
            .worst_location //
            .worst_city //
            .worst //
            .lowest_production //
            ""
        ' "$EXPECTED_FILE" 2>/dev/null || echo "")

        # Check if comparison array exists
        COMP_CHECK=$(jq -r "(.${COMP_ARRAY_NAME} // null) | type" "$EXPECTED_FILE" 2>/dev/null || echo "")
        if [ "$COMP_CHECK" = "array" ] && [ "$NUM_LOCATIONS" -gt "0" ]; then
            HAS_COMPARISON="true"
        fi

        # Extract per-city energy values with flexible key names
        # Try both .city and .location and .name for the city field, and .annual_kwh, .annual_energy, .energy_kwh for energy
        PHOENIX_KWH=$(jq -r "
            [.${COMP_ARRAY_NAME}[] |
             select((.city // .location // .name // \"\") | ascii_downcase | contains(\"phoenix\"))] |
            .[0] | (.annual_kwh // .annual_energy // .energy_kwh // .annual_energy_kwh // 0)
        " "$EXPECTED_FILE" 2>/dev/null || echo "0")

        TUCSON_KWH=$(jq -r "
            [.${COMP_ARRAY_NAME}[] |
             select((.city // .location // .name // \"\") | ascii_downcase | contains(\"tucson\"))] |
            .[0] | (.annual_kwh // .annual_energy // .energy_kwh // .annual_energy_kwh // 0)
        " "$EXPECTED_FILE" 2>/dev/null || echo "0")

        DES_MOINES_KWH=$(jq -r "
            [.${COMP_ARRAY_NAME}[] |
             select((.city // .location // .name // \"\") | ascii_downcase | (contains(\"des moines\") or contains(\"des_moines\")))] |
            .[0] | (.annual_kwh // .annual_energy // .energy_kwh // .annual_energy_kwh // 0)
        " "$EXPECTED_FILE" 2>/dev/null || echo "0")
    fi
fi

# Create JSON result safely using jq
jq -n \
    --argjson file_exists "$FILE_EXISTS" \
    --argjson file_size "$FILE_SIZE" \
    --argjson file_modified "$FILE_MODIFIED" \
    --argjson python_ran "$PYTHON_RAN" \
    --arg num_locations "$NUM_LOCATIONS" \
    --argjson has_comparison "$HAS_COMPARISON" \
    --arg best_location "$BEST_LOCATION" \
    --arg worst_location "$WORST_LOCATION" \
    --arg phoenix_kwh "$PHOENIX_KWH" \
    --arg tucson_kwh "$TUCSON_KWH" \
    --arg des_moines_kwh "$DES_MOINES_KWH" \
    --arg timestamp "$(date -Iseconds)" \
    '{
        file_exists: $file_exists,
        file_size: $file_size,
        file_modified: $file_modified,
        python_ran: $python_ran,
        num_locations: $num_locations,
        has_comparison: $has_comparison,
        best_location: $best_location,
        worst_location: $worst_location,
        phoenix_kwh: $phoenix_kwh,
        tucson_kwh: $tucson_kwh,
        des_moines_kwh: $des_moines_kwh,
        timestamp: $timestamp
    }' > /tmp/task_result.json

chmod 666 /tmp/task_result.json 2>/dev/null || true

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="
