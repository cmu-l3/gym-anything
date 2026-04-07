#!/bin/bash
echo "=== Exporting task result ==="

# Take final screenshot
DISPLAY=:1 import -window root /tmp/task_final.png 2>/dev/null || true

# Anti-bypass: Check if Python was actually used during the task
TASK_START=$(cat /home/ga/.task_start_time 2>/dev/null || echo "0")
PYTHON_RAN="false"

if [ -f /home/ga/.bash_history ]; then
    if grep -q "python3\|python " /home/ga/.bash_history 2>/dev/null; then
        PYTHON_RAN="true"
    fi
fi

# Check if expected Python script exists and has PySAM
SCRIPT_EXISTS="false"
SCRIPT_FILE="/home/ga/Documents/SAM_Projects/ev_fleet_analysis.py"
if [ -f "$SCRIPT_FILE" ]; then
    SCRIPT_EXISTS="true"
    if grep -ql "import PySAM\|from PySAM\|import Pvwatts\|Pvwattsv" "$SCRIPT_FILE" 2>/dev/null; then
        PYTHON_RAN="true"
    fi
fi

# Check JSON output file
JSON_FILE="/home/ga/Documents/SAM_Projects/ev_fleet_pv_analysis.json"
FILE_EXISTS="false"
FILE_MODIFIED="false"
FILE_SIZE=0

if [ -f "$JSON_FILE" ]; then
    FILE_EXISTS="true"
    FILE_SIZE=$(stat -c%s "$JSON_FILE" 2>/dev/null || echo "0")
    
    FILE_MTIME=$(stat -c%Y "$JSON_FILE" 2>/dev/null || echo "0")
    if [ "$FILE_MTIME" -gt "$TASK_START" ]; then
        FILE_MODIFIED="true"
    fi
fi

# Extract parameters from JSON using jq
PV_PROD="0"
LOAD_DEMAND="0"
GRID_IMPORT="0"
GRID_EXPORT="0"
COST_WITHOUT_PV="0"
COST_WITH_PV="0"
ANNUAL_SAVINGS="0"

if [ "$FILE_EXISTS" = "true" ] && command -v jq &> /dev/null; then
    if jq empty "$JSON_FILE" 2>/dev/null; then
        PV_PROD=$(jq -r '.pv_annual_production_kwh // "0"' "$JSON_FILE" 2>/dev/null)
        LOAD_DEMAND=$(jq -r '.load_annual_demand_kwh // "0"' "$JSON_FILE" 2>/dev/null)
        GRID_IMPORT=$(jq -r '.annual_grid_import_kwh // "0"' "$JSON_FILE" 2>/dev/null)
        GRID_EXPORT=$(jq -r '.annual_grid_export_kwh // "0"' "$JSON_FILE" 2>/dev/null)
        COST_WITHOUT_PV=$(jq -r '.cost_without_pv_usd // "0"' "$JSON_FILE" 2>/dev/null)
        COST_WITH_PV=$(jq -r '.cost_with_pv_usd // "0"' "$JSON_FILE" 2>/dev/null)
        ANNUAL_SAVINGS=$(jq -r '.annual_savings_usd // "0"' "$JSON_FILE" 2>/dev/null)
    fi
fi

# Export safely
jq -n \
    --argjson script_exists "$SCRIPT_EXISTS" \
    --argjson file_exists "$FILE_EXISTS" \
    --argjson file_modified "$FILE_MODIFIED" \
    --argjson file_size "$FILE_SIZE" \
    --argjson python_ran "$PYTHON_RAN" \
    --arg pv_prod "$PV_PROD" \
    --arg load_demand "$LOAD_DEMAND" \
    --arg grid_import "$GRID_IMPORT" \
    --arg grid_export "$GRID_EXPORT" \
    --arg cost_without_pv "$COST_WITHOUT_PV" \
    --arg cost_with_pv "$COST_WITH_PV" \
    --arg annual_savings "$ANNUAL_SAVINGS" \
    --arg timestamp "$(date -Iseconds)" \
    '{
        script_exists: $script_exists,
        file_exists: $file_exists,
        file_modified: $file_modified,
        file_size: $file_size,
        python_ran: $python_ran,
        pv_annual_production_kwh: $pv_prod,
        load_annual_demand_kwh: $load_demand,
        annual_grid_import_kwh: $grid_import,
        annual_grid_export_kwh: $grid_export,
        cost_without_pv_usd: $cost_without_pv,
        cost_with_pv_usd: $cost_with_pv,
        annual_savings_usd: $annual_savings,
        timestamp: $timestamp
    }' > /tmp/task_result.json

chmod 666 /tmp/task_result.json 2>/dev/null || true

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="