#!/bin/bash
echo "=== Exporting task result ==="

# Take final screenshot
DISPLAY=:1 import -window root /tmp/task_final.png 2>/dev/null || true

# Anti-bypass: Check if Python was actually used during the task
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
PYTHON_RAN="false"

if [ -f /home/ga/.bash_history ]; then
    if grep -q "python3\|python " /home/ga/.bash_history 2>/dev/null; then
        PYTHON_RAN="true"
    fi
fi

# Check if any .py files were created/modified after task start
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

# Check if expected file exists
EXPECTED_FILE="/home/ga/Documents/SAM_Projects/itc_vs_ptc_comparison.json"

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

# Initialize extracted variables
CAPACITY_KW="0"
ITC_ENERGY="0"
PTC_ENERGY="0"
ITC_LCOE="0"
PTC_LCOE="0"
ITC_NPV="0"
PTC_NPV="0"
ITC_PCT="0"
PTC_VAL="0"
VALID_JSON="false"

if [ -f "$EXPECTED_FILE" ] && command -v jq &> /dev/null; then
    if jq empty "$EXPECTED_FILE" 2>/dev/null; then
        VALID_JSON="true"
        
        CAPACITY_KW=$(jq -r '.system.capacity_kw // "0"' "$EXPECTED_FILE" 2>/dev/null || echo "0")
        
        ITC_ENERGY=$(jq -r '.itc_scenario.annual_energy_kwh // "0"' "$EXPECTED_FILE" 2>/dev/null || echo "0")
        ITC_LCOE=$(jq -r '.itc_scenario.lcoe_real // "0"' "$EXPECTED_FILE" 2>/dev/null || echo "0")
        ITC_NPV=$(jq -r '.itc_scenario.npv // "0"' "$EXPECTED_FILE" 2>/dev/null || echo "0")
        ITC_PCT=$(jq -r '.itc_scenario.itc_percent // "0"' "$EXPECTED_FILE" 2>/dev/null || echo "0")
        
        PTC_ENERGY=$(jq -r '.ptc_scenario.annual_energy_kwh // "0"' "$EXPECTED_FILE" 2>/dev/null || echo "0")
        PTC_LCOE=$(jq -r '.ptc_scenario.lcoe_real // "0"' "$EXPECTED_FILE" 2>/dev/null || echo "0")
        PTC_NPV=$(jq -r '.ptc_scenario.npv // "0"' "$EXPECTED_FILE" 2>/dev/null || echo "0")
        PTC_VAL=$(jq -r '.ptc_scenario.ptc_per_kwh // "0"' "$EXPECTED_FILE" 2>/dev/null || echo "0")
    fi
fi

# Create JSON result safely using jq
jq -n \
    --argjson file_exists "$FILE_EXISTS" \
    --argjson file_size "$FILE_SIZE" \
    --argjson file_modified "$FILE_MODIFIED" \
    --argjson valid_json "$VALID_JSON" \
    --argjson python_ran "$PYTHON_RAN" \
    --arg capacity_kw "$CAPACITY_KW" \
    --arg itc_energy "$ITC_ENERGY" \
    --arg itc_lcoe "$ITC_LCOE" \
    --arg itc_npv "$ITC_NPV" \
    --arg itc_pct "$ITC_PCT" \
    --arg ptc_energy "$PTC_ENERGY" \
    --arg ptc_lcoe "$PTC_LCOE" \
    --arg ptc_npv "$PTC_NPV" \
    --arg ptc_val "$PTC_VAL" \
    --arg timestamp "$(date -Iseconds)" \
    '{
        file_exists: $file_exists,
        file_size: $file_size,
        file_modified: $file_modified,
        valid_json: $valid_json,
        python_ran: $python_ran,
        capacity_kw: $capacity_kw,
        itc_energy: $itc_energy,
        itc_lcoe: $itc_lcoe,
        itc_npv: $itc_npv,
        itc_pct: $itc_pct,
        ptc_energy: $ptc_energy,
        ptc_lcoe: $ptc_lcoe,
        ptc_npv: $ptc_npv,
        ptc_val: $ptc_val,
        timestamp: $timestamp
    }' > /tmp/task_result.json

chmod 666 /tmp/task_result.json 2>/dev/null || true

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="