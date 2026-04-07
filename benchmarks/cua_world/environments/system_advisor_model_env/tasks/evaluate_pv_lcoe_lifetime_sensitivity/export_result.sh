#!/bin/bash
echo "=== Exporting task result ==="

# Record task end
TASK_START=$(cat /home/ga/.task_start_time 2>/dev/null || echo "0")

# Take final screenshot
DISPLAY=:1 import -window root /tmp/task_final.png 2>/dev/null || true

# Check if agent used Python
PYTHON_RAN="false"
if [ -f /home/ga/.bash_history ]; then
    if grep -q "python3\|python " /home/ga/.bash_history 2>/dev/null; then
        PYTHON_RAN="true"
    fi
fi

# Check expected script
SCRIPT_FILE="/home/ga/Documents/SAM_Projects/lcoe_calculator.py"
SCRIPT_EXISTS="false"
if [ -f "$SCRIPT_FILE" ]; then
    SCRIPT_EXISTS="true"
    # Basic check if PySAM was imported
    if grep -q "PySAM" "$SCRIPT_FILE"; then
        PYTHON_RAN="true"
    fi
fi

# Check expected JSON output
EXPECTED_FILE="/home/ga/Documents/SAM_Projects/lcoe_lifetime_sensitivity.json"
FILE_EXISTS="false"
FILE_MODIFIED="false"

YEAR1_ENERGY="0.0"
LCOE_25="0.0"
LCOE_30="0.0"
LCOE_35="0.0"

if [ -f "$EXPECTED_FILE" ]; then
    FILE_EXISTS="true"
    
    FILE_MTIME=$(stat -c%Y "$EXPECTED_FILE" 2>/dev/null || echo "0")
    if [ "$FILE_MTIME" -gt "$TASK_START" ]; then
        FILE_MODIFIED="true"
    fi
    
    # Extract values safely
    if command -v jq &> /dev/null; then
        YEAR1_ENERGY=$(jq -r '.year1_energy_kwh // .year1_energy // 0' "$EXPECTED_FILE" 2>/dev/null || echo "0.0")
        LCOE_25=$(jq -r '.lcoe_25_year // .lcoe_25 // 0' "$EXPECTED_FILE" 2>/dev/null || echo "0.0")
        LCOE_30=$(jq -r '.lcoe_30_year // .lcoe_30 // 0' "$EXPECTED_FILE" 2>/dev/null || echo "0.0")
        LCOE_35=$(jq -r '.lcoe_35_year // .lcoe_35 // 0' "$EXPECTED_FILE" 2>/dev/null || echo "0.0")
    fi
fi

# Export to verifiable result file
jq -n \
    --argjson file_exists "$FILE_EXISTS" \
    --argjson file_modified "$FILE_MODIFIED" \
    --argjson script_exists "$SCRIPT_EXISTS" \
    --argjson python_ran "$PYTHON_RAN" \
    --arg year1_energy "$YEAR1_ENERGY" \
    --arg lcoe_25 "$LCOE_25" \
    --arg lcoe_30 "$LCOE_30" \
    --arg lcoe_35 "$LCOE_35" \
    --arg timestamp "$(date -Iseconds)" \
    '{
        file_exists: $file_exists,
        file_modified: $file_modified,
        script_exists: $script_exists,
        python_ran: $python_ran,
        year1_energy_kwh: ($year1_energy | tonumber),
        lcoe_25_year: ($lcoe_25 | tonumber),
        lcoe_30_year: ($lcoe_30 | tonumber),
        lcoe_35_year: ($lcoe_35 | tonumber),
        timestamp: $timestamp
    }' > /tmp/task_result.json

chmod 666 /tmp/task_result.json 2>/dev/null || true

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="