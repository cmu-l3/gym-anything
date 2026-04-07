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
PY_FILES=$(find /home/ga /home/ga/Documents/SAM_Projects -name "*.py" -newer /home/ga/.task_start_time 2>/dev/null)
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
EXPECTED_FILE="/home/ga/Documents/SAM_Projects/denver_solar_lease_results.json"

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

# Extract presence of required keys using jq
HAS_REQUIRED_KEYS="false"
MISSING_KEYS=""
LOCATION_INFO=""

if [ -f "$EXPECTED_FILE" ] && command -v jq &> /dev/null; then
    if jq empty "$EXPECTED_FILE" 2>/dev/null; then
        
        # Check for required keys
        REQUIRED_KEYS=("location" "latitude" "longitude" "system_size_kw" "tilt_deg" "azimuth_deg" "ppa_price_cents_per_kwh" "ppa_escalation_pct" "annual_energy_kwh" "capacity_factor_pct" "year1_ppa_cost_usd" "year1_electricity_value_usd" "year1_savings_usd" "npv_of_savings_usd" "lcoe_nom_cents_per_kwh" "analysis_period_years")
        
        MISSING_COUNT=0
        for key in "${REQUIRED_KEYS[@]}"; do
            HAS_KEY=$(jq -r "has(\"$key\")" "$EXPECTED_FILE" 2>/dev/null || echo "false")
            if [ "$HAS_KEY" != "true" ]; then
                MISSING_COUNT=$((MISSING_COUNT + 1))
                MISSING_KEYS="$MISSING_KEYS $key"
            fi
        done
        
        if [ "$MISSING_COUNT" -eq 0 ]; then
            HAS_REQUIRED_KEYS="true"
        fi

        LOCATION_INFO=$(jq -r '.location // empty' "$EXPECTED_FILE" 2>/dev/null || echo "")
    fi
fi

# Create JSON result safely using jq
jq -n \
    --argjson file_exists "$FILE_EXISTS" \
    --argjson file_size "$FILE_SIZE" \
    --argjson file_modified "$FILE_MODIFIED" \
    --argjson python_ran "$PYTHON_RAN" \
    --argjson has_required_keys "$HAS_REQUIRED_KEYS" \
    --arg missing_keys "$MISSING_KEYS" \
    --arg location_info "$LOCATION_INFO" \
    --arg timestamp "$(date -Iseconds)" \
    '{
        file_exists: $file_exists,
        file_size: $file_size,
        file_modified: $file_modified,
        python_ran: $python_ran,
        has_required_keys: $has_required_keys,
        missing_keys: $missing_keys,
        location_info: $location_info,
        timestamp: $timestamp
    }' > /tmp/task_result.json

chmod 666 /tmp/task_result.json 2>/dev/null || true

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="