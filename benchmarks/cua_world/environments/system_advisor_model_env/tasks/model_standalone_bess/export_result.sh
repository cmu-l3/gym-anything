#!/bin/bash
echo "=== Exporting task result ==="

# Take final screenshot
DISPLAY=:1 import -window root /tmp/task_end.png 2>/dev/null || true

TASK_START=$(cat /home/ga/.task_start_time 2>/dev/null || echo "0")

# 1. Check Python Script
SCRIPT_FILE="/home/ga/Documents/SAM_Projects/bess_simulation.py"
SCRIPT_EXISTS="false"
if [ -f "$SCRIPT_FILE" ]; then
    SCRIPT_EXISTS="true"
fi

# 2. Check JSON File and Extract Data
JSON_FILE="/home/ga/Documents/SAM_Projects/bess_analysis_results.json"
JSON_EXISTS="false"
JSON_MODIFIED="false"

# Initialize variables to extract
BATTERY_POWER="0"
BATTERY_CAPACITY="0"
CHARGE_ENERGY="0"
DISCHARGE_ENERGY="0"
RTE="0"
EFC="0"
SIM_HOURS="0"
IS_VALID_JSON="false"

if [ -f "$JSON_FILE" ]; then
    JSON_EXISTS="true"
    
    FILE_MTIME=$(stat -c%Y "$JSON_FILE" 2>/dev/null || echo "0")
    if [ "$FILE_MTIME" -gt "$TASK_START" ]; then
        JSON_MODIFIED="true"
    fi
    
    # Try parsing the JSON
    if command -v jq &> /dev/null; then
        if jq empty "$JSON_FILE" 2>/dev/null; then
            IS_VALID_JSON="true"
            
            # Extract metrics using jq, defaulting to 0 if missing
            BATTERY_POWER=$(jq -r '.battery_power_kw // 0' "$JSON_FILE" 2>/dev/null)
            BATTERY_CAPACITY=$(jq -r '.battery_capacity_kwh // 0' "$JSON_FILE" 2>/dev/null)
            CHARGE_ENERGY=$(jq -r '.annual_charge_energy_kwh // 0' "$JSON_FILE" 2>/dev/null)
            DISCHARGE_ENERGY=$(jq -r '.annual_discharge_energy_kwh // 0' "$JSON_FILE" 2>/dev/null)
            RTE=$(jq -r '.roundtrip_efficiency_pct // 0' "$JSON_FILE" 2>/dev/null)
            EFC=$(jq -r '.equivalent_full_cycles // 0' "$JSON_FILE" 2>/dev/null)
            SIM_HOURS=$(jq -r '.simulation_hours // 0' "$JSON_FILE" 2>/dev/null)
        fi
    fi
fi

# Create JSON result safely
jq -n \
    --argjson script_exists "$SCRIPT_EXISTS" \
    --argjson json_exists "$JSON_EXISTS" \
    --argjson json_modified "$JSON_MODIFIED" \
    --argjson is_valid_json "$IS_VALID_JSON" \
    --arg battery_power "$BATTERY_POWER" \
    --arg battery_capacity "$BATTERY_CAPACITY" \
    --arg charge_energy "$CHARGE_ENERGY" \
    --arg discharge_energy "$DISCHARGE_ENERGY" \
    --arg rte "$RTE" \
    --arg efc "$EFC" \
    --arg sim_hours "$SIM_HOURS" \
    --arg timestamp "$(date -Iseconds)" \
    '{
        script_exists: $script_exists,
        json_exists: $json_exists,
        json_modified: $json_modified,
        is_valid_json: $is_valid_json,
        battery_power: $battery_power,
        battery_capacity: $battery_capacity,
        charge_energy: $charge_energy,
        discharge_energy: $discharge_energy,
        rte: $rte,
        efc: $efc,
        sim_hours: $sim_hours,
        timestamp: $timestamp
    }' > /tmp/task_result.json

chmod 666 /tmp/task_result.json 2>/dev/null || true

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="