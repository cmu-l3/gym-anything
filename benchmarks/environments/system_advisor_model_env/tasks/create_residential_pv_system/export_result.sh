#!/bin/bash
echo "=== Exporting task result ==="

# Take final screenshot
DISPLAY=:1 import -window root /tmp/task_end.png 2>/dev/null || true

# Anti-bypass: Check if Python was actually used during the task
TASK_START=$(cat /home/ga/.task_start_time 2>/dev/null || echo "0")
PYTHON_RAN="false"

# Check bash history for python3 commands
if [ -f /home/ga/.bash_history ]; then
    if grep -q "python3\|python " /home/ga/.bash_history 2>/dev/null; then
        PYTHON_RAN="true"
    fi
fi

# Check if any .py files were created/modified after task start AND contain PySAM imports
PY_FILES=$(find /home/ga -name "*.py" -newer /home/ga/.task_start_time 2>/dev/null)
if [ -n "$PY_FILES" ]; then
    # Verify at least one .py file contains actual PySAM/simulation imports
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
EXPECTED_FILE="/home/ga/Documents/SAM_Projects/Phoenix_Residential_5kW.json"
if [ ! -f "$EXPECTED_FILE" ]; then
    EXPECTED_FILE="/home/ga/Documents/SAM_Projects/Phoenix_Residential_5kW.sam"
fi

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

# Extract parameters from JSON result file using flexible key paths
LOCATION_INFO=""
DC_SIZE="0"
TILT="0"
AZIMUTH="0"
ANNUAL_KWH="0"
CAPACITY_FACTOR="0"

if [ -f "$EXPECTED_FILE" ] && command -v jq &> /dev/null; then
    # Validate it's actually valid JSON
    if jq empty "$EXPECTED_FILE" 2>/dev/null; then
        # Try multiple common key paths for each field
        LOCATION_INFO=$(jq -r '
            .location.city //
            .city //
            .location //
            .site //
            empty
        ' "$EXPECTED_FILE" 2>/dev/null || echo "")

        DC_SIZE=$(jq -r '
            .configuration.system_capacity_kw //
            .system_capacity //
            .configuration.system_capacity //
            .configuration.dc_capacity_kw //
            .dc_size_kw //
            .system_capacity_kw //
            "0"
        ' "$EXPECTED_FILE" 2>/dev/null || echo "0")

        TILT=$(jq -r '
            .configuration.tilt_deg //
            .configuration.tilt //
            .tilt //
            .tilt_deg //
            "0"
        ' "$EXPECTED_FILE" 2>/dev/null || echo "0")

        AZIMUTH=$(jq -r '
            .configuration.azimuth_deg //
            .configuration.azimuth //
            .azimuth //
            .azimuth_deg //
            "0"
        ' "$EXPECTED_FILE" 2>/dev/null || echo "0")

        ANNUAL_KWH=$(jq -r '
            .annual_results.ac_annual_kwh //
            .results.annual_energy //
            .annual_energy_kwh //
            .annual_kwh //
            .ac_annual //
            .annual_results.annual_energy //
            "0"
        ' "$EXPECTED_FILE" 2>/dev/null || echo "0")

        CAPACITY_FACTOR=$(jq -r '
            .annual_results.capacity_factor_pct //
            .results.capacity_factor //
            .capacity_factor //
            .capacity_factor_pct //
            "0"
        ' "$EXPECTED_FILE" 2>/dev/null || echo "0")

        # If location empty or just "-", derive from weather file path
        if [ -z "$LOCATION_INFO" ] || [ "$LOCATION_INFO" = "-" ] || [ "$LOCATION_INFO" = "null" ]; then
            WF=$(jq -r '.. | select(type=="string") | select(test("phoenix"; "i"))' "$EXPECTED_FILE" 2>/dev/null | head -1 || echo "")
            if [ -n "$WF" ]; then
                LOCATION_INFO="phoenix"
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
    --arg dc_size "$DC_SIZE" \
    --arg tilt "$TILT" \
    --arg azimuth "$AZIMUTH" \
    --arg annual_kwh "$ANNUAL_KWH" \
    --arg capacity_factor "$CAPACITY_FACTOR" \
    --arg timestamp "$(date -Iseconds)" \
    '{
        file_exists: $file_exists,
        file_size: $file_size,
        file_modified: $file_modified,
        python_ran: $python_ran,
        location_info: $location_info,
        dc_size: $dc_size,
        tilt: $tilt,
        azimuth: $azimuth,
        annual_kwh: $annual_kwh,
        capacity_factor: $capacity_factor,
        timestamp: $timestamp
    }' > /tmp/task_result.json

chmod 666 /tmp/task_result.json 2>/dev/null || true

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="
