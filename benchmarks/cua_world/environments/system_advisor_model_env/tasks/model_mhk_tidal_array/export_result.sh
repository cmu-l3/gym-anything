#!/bin/bash
echo "=== Exporting task result ==="

# Take final screenshot
DISPLAY=:1 import -window root /tmp/task_end.png 2>/dev/null || true

TASK_START=$(cat /home/ga/.task_start_time 2>/dev/null || echo "0")
SCRIPT_FILE="/home/ga/Documents/SAM_Projects/tidal_array_model.py"
JSON_FILE="/home/ga/Documents/SAM_Projects/tidal_array_results.json"

SCRIPT_EXISTS="false"
SCRIPT_MODIFIED="false"
SCRIPT_IMPORTS_PYSAM="false"
SCRIPT_IMPORTS_MHK="false"

if [ -f "$SCRIPT_FILE" ]; then
    SCRIPT_EXISTS="true"
    FILE_MTIME=$(stat -c%Y "$SCRIPT_FILE" 2>/dev/null || echo "0")
    if [ "$FILE_MTIME" -gt "$TASK_START" ]; then
        SCRIPT_MODIFIED="true"
    fi
    if grep -q "PySAM" "$SCRIPT_FILE"; then SCRIPT_IMPORTS_PYSAM="true"; fi
    if grep -qi "MhkTidal" "$SCRIPT_FILE"; then SCRIPT_IMPORTS_MHK="true"; fi
fi

JSON_EXISTS="false"
JSON_MODIFIED="false"

if [ -f "$JSON_FILE" ]; then
    JSON_EXISTS="true"
    FILE_MTIME=$(stat -c%Y "$JSON_FILE" 2>/dev/null || echo "0")
    if [ "$FILE_MTIME" -gt "$TASK_START" ]; then
        JSON_MODIFIED="true"
    fi
fi

# Use Python to safely parse the agent's JSON and extract specific fields
python3 -c "
import json, sys
try:
    with open('$JSON_FILE', 'r') as f:
        d = json.load(f)
    out = {
        'annual_energy_kwh': float(d.get('annual_energy_kwh', 0)),
        'capacity_factor_percent': float(d.get('capacity_factor_percent', 0)),
        'device_average_power_kw': float(d.get('device_average_power_kw', 0)),
        'number_devices': int(d.get('number_devices', 0)),
        'device_rated_capacity_kw': float(d.get('device_rated_capacity_kw', 0)),
        'total_system_capacity_kw': float(d.get('total_system_capacity_kw', 0)),
        'lcoe_cents_per_kwh': float(d.get('lcoe_cents_per_kwh', 0)),
        'total_capital_cost_usd': float(d.get('total_capital_cost_usd', 0)),
        'annual_om_cost_usd': float(d.get('annual_om_cost_usd', 0))
    }
except Exception as e:
    out = {
        'error': str(e),
        'annual_energy_kwh': 0.0,
        'capacity_factor_percent': 0.0,
        'device_average_power_kw': 0.0,
        'number_devices': 0,
        'device_rated_capacity_kw': 0.0,
        'total_system_capacity_kw': 0.0,
        'lcoe_cents_per_kwh': 0.0,
        'total_capital_cost_usd': 0.0,
        'annual_om_cost_usd': 0.0
    }
with open('/tmp/parsed_json.json', 'w') as f:
    json.dump(out, f)
" 2>/dev/null

# Create JSON result safely using jq
jq -n \
    --argjson script_exists "$SCRIPT_EXISTS" \
    --argjson script_modified "$SCRIPT_MODIFIED" \
    --argjson imports_pysam "$SCRIPT_IMPORTS_PYSAM" \
    --argjson imports_mhk "$SCRIPT_IMPORTS_MHK" \
    --argjson json_exists "$JSON_EXISTS" \
    --argjson json_modified "$JSON_MODIFIED" \
    --slurpfile data /tmp/parsed_json.json \
    --arg timestamp "$(date -Iseconds)" \
    '{
        script_exists: $script_exists,
        script_modified: $script_modified,
        imports_pysam: $imports_pysam,
        imports_mhk: $imports_mhk,
        json_exists: $json_exists,
        json_modified: $json_modified,
        data: $data[0],
        timestamp: $timestamp
    }' > /tmp/task_result.json

chmod 666 /tmp/task_result.json 2>/dev/null || true

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="