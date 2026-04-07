#!/bin/bash
echo "=== Exporting task result ==="

# Take final screenshot
DISPLAY=:1 import -window root /tmp/task_end.png 2>/dev/null || true

# Anti-bypass: Check timestamps
TASK_START=$(cat /home/ga/.task_start_time 2>/dev/null || echo "0")
PYTHON_RAN="false"

if [ -f /home/ga/.bash_history ]; then
    if grep -q "python3\|python " /home/ga/.bash_history 2>/dev/null; then
        PYTHON_RAN="true"
    fi
fi

# Check for the expected Python script
SCRIPT_FILE="/home/ga/Documents/SAM_Projects/compute_lcoe.py"
SCRIPT_EXISTS="false"
SCRIPT_HAS_IMPORTS="false"
SCRIPT_HAS_MODULES="false"
SCRIPT_HAS_PARAMS="false"

if [ -f "$SCRIPT_FILE" ]; then
    SCRIPT_EXISTS="true"
    
    if grep -ql "import PySAM\|from PySAM" "$SCRIPT_FILE" 2>/dev/null; then
        SCRIPT_HAS_IMPORTS="true"
    fi
    
    if grep -q "Pvwatts" "$SCRIPT_FILE" 2>/dev/null && grep -q "Lcoefcr" "$SCRIPT_FILE" 2>/dev/null; then
        SCRIPT_HAS_MODULES="true"
    fi
    
    if grep -q "100000" "$SCRIPT_FILE" 2>/dev/null && grep -q "0.0713" "$SCRIPT_FILE" 2>/dev/null; then
        SCRIPT_HAS_PARAMS="true"
    fi
fi

# Check for the expected JSON result file
JSON_FILE="/home/ga/Documents/SAM_Projects/utility_pv_lcoe_result.json"
JSON_EXISTS="false"
JSON_MODIFIED="false"
HAS_ALL_KEYS="false"

ANNUAL_ENERGY="0"
CAPACITY_FACTOR="0"
LCOE="0"
WEATHER_FILE=""

if [ -f "$JSON_FILE" ]; then
    JSON_EXISTS="true"
    FILE_MTIME=$(stat -c%Y "$JSON_FILE" 2>/dev/null || echo "0")
    if [ "$FILE_MTIME" -gt "$TASK_START" ]; then
        JSON_MODIFIED="true"
    fi
    
    # Parse JSON safely
    if command -v jq &> /dev/null && ! jq empty "$JSON_FILE" >/dev/null 2>&1; then
        ANNUAL_ENERGY=$(jq -r '.annual_energy_kwh // "0"' "$JSON_FILE" 2>/dev/null || echo "0")
        CAPACITY_FACTOR=$(jq -r '.capacity_factor_pct // "0"' "$JSON_FILE" 2>/dev/null || echo "0")
        LCOE=$(jq -r '.lcoe_cents_per_kwh // "0"' "$JSON_FILE" 2>/dev/null || echo "0")
        WEATHER_FILE=$(jq -r '.weather_file_used // ""' "$JSON_FILE" 2>/dev/null || echo "")
        
        # Check if all keys exist and are not null
        HAS_KEYS=$(jq -r 'has("annual_energy_kwh") and has("capacity_factor_pct") and has("lcoe_cents_per_kwh") and has("weather_file_used")' "$JSON_FILE" 2>/dev/null || echo "false")
        if [ "$HAS_KEYS" = "true" ]; then
            HAS_ALL_KEYS="true"
        fi
    fi
fi

# Create JSON result safely using jq
jq -n \
    --argjson script_exists "$SCRIPT_EXISTS" \
    --argjson script_has_imports "$SCRIPT_HAS_IMPORTS" \
    --argjson script_has_modules "$SCRIPT_HAS_MODULES" \
    --argjson script_has_params "$SCRIPT_HAS_PARAMS" \
    --argjson json_exists "$JSON_EXISTS" \
    --argjson json_modified "$JSON_MODIFIED" \
    --argjson has_all_keys "$HAS_ALL_KEYS" \
    --argjson python_ran "$PYTHON_RAN" \
    --arg annual_energy "$ANNUAL_ENERGY" \
    --arg capacity_factor "$CAPACITY_FACTOR" \
    --arg lcoe "$LCOE" \
    --arg weather_file "$WEATHER_FILE" \
    --arg timestamp "$(date -Iseconds)" \
    '{
        script_exists: $script_exists,
        script_has_imports: $script_has_imports,
        script_has_modules: $script_has_modules,
        script_has_params: $script_has_params,
        json_exists: $json_exists,
        json_modified: $json_modified,
        has_all_keys: $has_all_keys,
        python_ran: $python_ran,
        annual_energy: $annual_energy,
        capacity_factor: $capacity_factor,
        lcoe: $lcoe,
        weather_file: $weather_file,
        timestamp: $timestamp
    }' > /tmp/task_result.json

chmod 666 /tmp/task_result.json 2>/dev/null || true

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="