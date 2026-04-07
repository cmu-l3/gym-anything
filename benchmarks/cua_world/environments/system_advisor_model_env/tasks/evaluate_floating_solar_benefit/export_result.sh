#!/bin/bash
echo "=== Exporting evaluate_floating_solar_benefit task result ==="

# Take final screenshot
DISPLAY=:1 import -window root /tmp/task_final.png 2>/dev/null || true

TASK_START=$(cat /home/ga/.task_start_time 2>/dev/null || echo "0")
PYTHON_RAN="false"

# Check if python was run
if [ -f /home/ga/.bash_history ]; then
    if grep -q "python3\|python " /home/ga/.bash_history 2>/dev/null; then
        PYTHON_RAN="true"
    fi
fi

# Check if any .py files were created/modified after task start AND contain PySAM imports
PY_FILES=$(find /home/ga -name "*.py" -newer /home/ga/.task_start_time 2>/dev/null)
if [ -n "$PY_FILES" ]; then
    for pyf in $PY_FILES; do
        if grep -ql "import PySAM\|from PySAM\|import Pvwatts\|Pvwattsv" "$pyf" 2>/dev/null; then
            PYTHON_RAN="true"
            break
        fi
    done
fi

EXPECTED_FILE="/home/ga/Documents/SAM_Projects/floating_pv_analysis.json"
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

# Initialize JSON fields
CAPACITY="0"
TILT="0"
AZIMUTH="0"
GROUND_INOCT="0"
FLOATING_INOCT="0"
GROUND_ENERGY="0"
FLOATING_ENERGY="0"
ENERGY_GAIN="0"
GAIN_PERCENT="0"

# Parse JSON safely using jq if valid
if [ "$FILE_EXISTS" = "true" ] && command -v jq &> /dev/null; then
    if jq empty "$EXPECTED_FILE" 2>/dev/null; then
        CAPACITY=$(jq -r '.system_capacity_kw // "0"' "$EXPECTED_FILE" 2>/dev/null || echo "0")
        TILT=$(jq -r '.tilt_deg // "0"' "$EXPECTED_FILE" 2>/dev/null || echo "0")
        AZIMUTH=$(jq -r '.azimuth_deg // "0"' "$EXPECTED_FILE" 2>/dev/null || echo "0")
        GROUND_INOCT=$(jq -r '.ground_inoct_c // "0"' "$EXPECTED_FILE" 2>/dev/null || echo "0")
        FLOATING_INOCT=$(jq -r '.floating_inoct_c // "0"' "$EXPECTED_FILE" 2>/dev/null || echo "0")
        GROUND_ENERGY=$(jq -r '.ground_annual_energy_kwh // "0"' "$EXPECTED_FILE" 2>/dev/null || echo "0")
        FLOATING_ENERGY=$(jq -r '.floating_annual_energy_kwh // "0"' "$EXPECTED_FILE" 2>/dev/null || echo "0")
        ENERGY_GAIN=$(jq -r '.energy_gain_kwh // "0"' "$EXPECTED_FILE" 2>/dev/null || echo "0")
        GAIN_PERCENT=$(jq -r '.gain_percent // "0"' "$EXPECTED_FILE" 2>/dev/null || echo "0")
    fi
fi

# Create a master result JSON combining metadata and extracted data
jq -n \
    --argjson file_exists "$FILE_EXISTS" \
    --argjson file_size "$FILE_SIZE" \
    --argjson file_modified "$FILE_MODIFIED" \
    --argjson python_ran "$PYTHON_RAN" \
    --arg capacity "$CAPACITY" \
    --arg tilt "$TILT" \
    --arg azimuth "$AZIMUTH" \
    --arg ground_inoct "$GROUND_INOCT" \
    --arg floating_inoct "$FLOATING_INOCT" \
    --arg ground_energy "$GROUND_ENERGY" \
    --arg floating_energy "$FLOATING_ENERGY" \
    --arg energy_gain "$ENERGY_GAIN" \
    --arg gain_percent "$GAIN_PERCENT" \
    --arg timestamp "$(date -Iseconds)" \
    '{
        file_exists: $file_exists,
        file_size: $file_size,
        file_modified: $file_modified,
        python_ran: $python_ran,
        capacity: $capacity,
        tilt: $tilt,
        azimuth: $azimuth,
        ground_inoct: $ground_inoct,
        floating_inoct: $floating_inoct,
        ground_energy: $ground_energy,
        floating_energy: $floating_energy,
        energy_gain: $energy_gain,
        gain_percent: $gain_percent,
        timestamp: $timestamp
    }' > /tmp/task_result.json

chmod 666 /tmp/task_result.json 2>/dev/null || true

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="