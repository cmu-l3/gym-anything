#!/bin/bash
echo "=== Exporting task result ==="

# Take final screenshot
DISPLAY=:1 import -window root /tmp/task_end.png 2>/dev/null || true

# Get task start time for anti-gaming checks
TASK_START=$(cat /home/ga/.task_start_time 2>/dev/null || echo "0")

# Check if Python was actually used
PYTHON_RAN="false"
if [ -f /home/ga/.bash_history ]; then
    if grep -q "python3\|python " /home/ga/.bash_history 2>/dev/null; then
        PYTHON_RAN="true"
    fi
fi

# Define expected files
EXPECTED_JSON="/home/ga/Documents/SAM_Projects/capacity_value_report.json"
EXPECTED_PY="/home/ga/Documents/SAM_Projects/calc_capacity_value.py"

JSON_EXISTS="false"
JSON_SIZE=0
JSON_MODIFIED="false"

PY_EXISTS="false"
PY_SIZE=0
PY_MODIFIED="false"
PYSAM_IMPORTED="false"

# Check JSON
if [ -f "$EXPECTED_JSON" ]; then
    JSON_EXISTS="true"
    JSON_SIZE=$(stat -c%s "$EXPECTED_JSON" 2>/dev/null || echo "0")
    JSON_MTIME=$(stat -c%Y "$EXPECTED_JSON" 2>/dev/null || echo "0")
    if [ "$JSON_MTIME" -gt "$TASK_START" ]; then
        JSON_MODIFIED="true"
    fi
fi

# Check Python script
if [ -f "$EXPECTED_PY" ]; then
    PY_EXISTS="true"
    PY_SIZE=$(stat -c%s "$EXPECTED_PY" 2>/dev/null || echo "0")
    PY_MTIME=$(stat -c%Y "$EXPECTED_PY" 2>/dev/null || echo "0")
    if [ "$PY_MTIME" -gt "$TASK_START" ]; then
        PY_MODIFIED="true"
    fi
    
    if grep -ql "import PySAM\|from PySAM\|import Pvwatts" "$EXPECTED_PY" 2>/dev/null; then
        PYSAM_IMPORTED="true"
        PYTHON_RAN="true"
    fi
fi

# Extract parameters from JSON safely
DC_CAPACITY="0"
MAX_AC_CAPACITY="0"
TILT="0"
AZIMUTH="0"
SUMMER_PEAK_KW="0"
CAPACITY_PERCENT="0"
WEATHER_FILE=""

if [ "$JSON_EXISTS" = "true" ] && command -v jq &> /dev/null; then
    if jq empty "$EXPECTED_JSON" 2>/dev/null; then
        DC_CAPACITY=$(jq -r '.system_capacity_kw_dc // 0' "$EXPECTED_JSON" 2>/dev/null || echo "0")
        MAX_AC_CAPACITY=$(jq -r '.max_ac_capacity_kw // 0' "$EXPECTED_JSON" 2>/dev/null || echo "0")
        TILT=$(jq -r '.tilt_deg // 0' "$EXPECTED_JSON" 2>/dev/null || echo "0")
        AZIMUTH=$(jq -r '.azimuth_deg // 0' "$EXPECTED_JSON" 2>/dev/null || echo "0")
        SUMMER_PEAK_KW=$(jq -r '.summer_peak_average_kw_ac // 0' "$EXPECTED_JSON" 2>/dev/null || echo "0")
        CAPACITY_PERCENT=$(jq -r '.capacity_value_percent // 0' "$EXPECTED_JSON" 2>/dev/null || echo "0")
        WEATHER_FILE=$(jq -r '.weather_file_used // ""' "$EXPECTED_JSON" 2>/dev/null || echo "")
    fi
fi

# Package into task_result.json
jq -n \
    --argjson json_exists "$JSON_EXISTS" \
    --argjson json_size "$JSON_SIZE" \
    --argjson json_modified "$JSON_MODIFIED" \
    --argjson py_exists "$PY_EXISTS" \
    --argjson py_size "$PY_SIZE" \
    --argjson py_modified "$PY_MODIFIED" \
    --argjson pysam_imported "$PYSAM_IMPORTED" \
    --argjson python_ran "$PYTHON_RAN" \
    --arg dc_capacity "$DC_CAPACITY" \
    --arg max_ac_capacity "$MAX_AC_CAPACITY" \
    --arg tilt "$TILT" \
    --arg azimuth "$AZIMUTH" \
    --arg summer_peak_kw "$SUMMER_PEAK_KW" \
    --arg capacity_percent "$CAPACITY_PERCENT" \
    --arg weather_file "$WEATHER_FILE" \
    --arg timestamp "$(date -Iseconds)" \
    '{
        json_exists: $json_exists,
        json_size: $json_size,
        json_modified: $json_modified,
        py_exists: $py_exists,
        py_size: $py_size,
        py_modified: $py_modified,
        pysam_imported: $pysam_imported,
        python_ran: $python_ran,
        dc_capacity: $dc_capacity,
        max_ac_capacity: $max_ac_capacity,
        tilt: $tilt,
        azimuth: $azimuth,
        summer_peak_kw: $summer_peak_kw,
        capacity_percent: $capacity_percent,
        weather_file: $weather_file,
        timestamp: $timestamp
    }' > /tmp/task_result.json

chmod 666 /tmp/task_result.json 2>/dev/null || true

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="