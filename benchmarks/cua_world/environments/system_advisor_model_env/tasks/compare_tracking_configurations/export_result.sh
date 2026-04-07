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
EXPECTED_FILE="/home/ga/Documents/SAM_Projects/tracking_comparison.json"

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

# Parse JSON values using jq to ensure it's valid
VALID_JSON="false"
LOCATION=""
CAPACITY=0
FIXED_ENERGY=0
FIXED_CF=0
SINGLE_ENERGY=0
SINGLE_CF=0
DUAL_ENERGY=0
DUAL_CF=0
RECOMMENDATION=""

if [ "$FILE_EXISTS" = "true" ] && command -v jq &> /dev/null; then
    if jq empty "$EXPECTED_FILE" 2>/dev/null; then
        VALID_JSON="true"
        
        LOCATION=$(jq -r '.location // ""' "$EXPECTED_FILE" 2>/dev/null)
        CAPACITY=$(jq -r '.system_capacity_kw // 0' "$EXPECTED_FILE" 2>/dev/null)
        RECOMMENDATION=$(jq -r '.recommended_tracking // ""' "$EXPECTED_FILE" 2>/dev/null)
        
        # Get energies and CFs for the three configurations based on array_type
        FIXED_ENERGY=$(jq -r '.configurations[]? | select(.array_type == 0) | .annual_energy_kwh // 0' "$EXPECTED_FILE" | head -n 1)
        FIXED_CF=$(jq -r '.configurations[]? | select(.array_type == 0) | .capacity_factor_pct // 0' "$EXPECTED_FILE" | head -n 1)
        
        SINGLE_ENERGY=$(jq -r '.configurations[]? | select(.array_type == 2) | .annual_energy_kwh // 0' "$EXPECTED_FILE" | head -n 1)
        SINGLE_CF=$(jq -r '.configurations[]? | select(.array_type == 2) | .capacity_factor_pct // 0' "$EXPECTED_FILE" | head -n 1)
        
        DUAL_ENERGY=$(jq -r '.configurations[]? | select(.array_type == 4) | .annual_energy_kwh // 0' "$EXPECTED_FILE" | head -n 1)
        DUAL_CF=$(jq -r '.configurations[]? | select(.array_type == 4) | .capacity_factor_pct // 0' "$EXPECTED_FILE" | head -n 1)
    fi
fi

# Defaults if jq extraction failed or returned empty
FIXED_ENERGY=${FIXED_ENERGY:-0}
FIXED_CF=${FIXED_CF:-0}
SINGLE_ENERGY=${SINGLE_ENERGY:-0}
SINGLE_CF=${SINGLE_CF:-0}
DUAL_ENERGY=${DUAL_ENERGY:-0}
DUAL_CF=${DUAL_CF:-0}
CAPACITY=${CAPACITY:-0}

# Create JSON result safely using jq
jq -n \
    --argjson file_exists "$FILE_EXISTS" \
    --argjson file_size "$FILE_SIZE" \
    --argjson file_modified "$FILE_MODIFIED" \
    --argjson python_ran "$PYTHON_RAN" \
    --argjson valid_json "$VALID_JSON" \
    --arg location "$LOCATION" \
    --argjson capacity "$CAPACITY" \
    --arg recommendation "$RECOMMENDATION" \
    --argjson fixed_energy "$FIXED_ENERGY" \
    --argjson fixed_cf "$FIXED_CF" \
    --argjson single_energy "$SINGLE_ENERGY" \
    --argjson single_cf "$SINGLE_CF" \
    --argjson dual_energy "$DUAL_ENERGY" \
    --argjson dual_cf "$DUAL_CF" \
    --arg timestamp "$(date -Iseconds)" \
    '{
        file_exists: $file_exists,
        file_size: $file_size,
        file_modified: $file_modified,
        python_ran: $python_ran,
        valid_json: $valid_json,
        location: $location,
        capacity: $capacity,
        recommendation: $recommendation,
        fixed_energy: $fixed_energy,
        fixed_cf: $fixed_cf,
        single_energy: $single_energy,
        single_cf: $single_cf,
        dual_energy: $dual_energy,
        dual_cf: $dual_cf,
        timestamp: $timestamp
    }' > /tmp/task_result.json

chmod 666 /tmp/task_result.json 2>/dev/null || true

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="