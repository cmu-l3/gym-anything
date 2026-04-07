#!/bin/bash
echo "=== Exporting task result ==="

# Take final screenshot
DISPLAY=:1 import -window root /tmp/task_final.png 2>/dev/null || \
    DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# Check if Python was actually used during the task
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
PYTHON_RAN="false"

if [ -f /home/ga/.bash_history ]; then
    if grep -q "python3\|python " /home/ga/.bash_history 2>/dev/null; then
        PYTHON_RAN="true"
    fi
fi

# Check if any .py files were created/modified after task start AND contain PySAM imports
PY_FILES=$(find /home/ga -name "*.py" -newer /tmp/task_start_time.txt 2>/dev/null)
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

EXPECTED_FILE="/home/ga/Documents/SAM_Projects/thermal_derating_comparison.json"
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

# Extract key parameters safely using jq (with fallbacks if malformed)
SYS_CAP="0"
OPEN_ENERGY="0"
OPEN_TEMP="0"
ROOF_ENERGY="0"
ROOF_TEMP="0"
PENALTY="0"
WEATHER_FILE=""

if [ -f "$EXPECTED_FILE" ] && command -v jq &> /dev/null; then
    if jq empty "$EXPECTED_FILE" 2>/dev/null; then
        SYS_CAP=$(jq -r '.system_capacity_kw // "0"' "$EXPECTED_FILE" 2>/dev/null || echo "0")
        WEATHER_FILE=$(jq -r '.weather_file_used // ""' "$EXPECTED_FILE" 2>/dev/null || echo "")
        
        OPEN_ENERGY=$(jq -r '.open_rack.annual_energy_kwh // "0"' "$EXPECTED_FILE" 2>/dev/null || echo "0")
        OPEN_TEMP=$(jq -r '.open_rack.mean_cell_temp_c // "0"' "$EXPECTED_FILE" 2>/dev/null || echo "0")
        
        ROOF_ENERGY=$(jq -r '.roof_mount.annual_energy_kwh // "0"' "$EXPECTED_FILE" 2>/dev/null || echo "0")
        ROOF_TEMP=$(jq -r '.roof_mount.mean_cell_temp_c // "0"' "$EXPECTED_FILE" 2>/dev/null || echo "0")
        
        PENALTY=$(jq -r '.thermal_derating_penalty_percent // "0"' "$EXPECTED_FILE" 2>/dev/null || echo "0")
    fi
fi

# Create JSON export payload
jq -n \
    --argjson file_exists "$FILE_EXISTS" \
    --argjson file_size "$FILE_SIZE" \
    --argjson file_modified "$FILE_MODIFIED" \
    --argjson python_ran "$PYTHON_RAN" \
    --arg sys_cap "$SYS_CAP" \
    --arg open_energy "$OPEN_ENERGY" \
    --arg open_temp "$OPEN_TEMP" \
    --arg roof_energy "$ROOF_ENERGY" \
    --arg roof_temp "$ROOF_TEMP" \
    --arg penalty "$PENALTY" \
    --arg weather_file "$WEATHER_FILE" \
    --arg timestamp "$(date -Iseconds)" \
    '{
        file_exists: $file_exists,
        file_size: $file_size,
        file_modified: $file_modified,
        python_ran: $python_ran,
        system_capacity_kw: $sys_cap,
        open_energy: $open_energy,
        open_temp: $open_temp,
        roof_energy: $roof_energy,
        roof_temp: $roof_temp,
        penalty_percent: $penalty,
        weather_file: $weather_file,
        timestamp: $timestamp
    }' > /tmp/task_result.json

chmod 666 /tmp/task_result.json 2>/dev/null || true

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="