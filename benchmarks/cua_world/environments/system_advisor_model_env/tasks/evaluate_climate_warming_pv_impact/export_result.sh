#!/bin/bash
echo "=== Exporting task result ==="

# Take final screenshot
DISPLAY=:1 import -window root /tmp/task_end.png 2>/dev/null || true

TASK_START=$(cat /home/ga/.task_start_time 2>/dev/null || echo "0")

# Anti-bypass: Check if Python was used
PYTHON_RAN="false"
if [ -f /home/ga/.bash_history ] && grep -q "python3\|python " /home/ga/.bash_history 2>/dev/null; then
    PYTHON_RAN="true"
fi

PY_FILES=$(find /home/ga -name "*.py" -newer /home/ga/.task_start_time 2>/dev/null)
if [ -n "$PY_FILES" ]; then
    if grep -ql "import PySAM\|from PySAM\|import Pvwatts\|Pvwattsv\|import pandas\|import csv" $PY_FILES 2>/dev/null; then
        PYTHON_RAN="true"
    fi
fi

# Paths to evaluate
MOD_CSV_FILE="/home/ga/SAM_Weather_Data/phoenix_plus_3c.csv"
JSON_FILE="/home/ga/Documents/SAM_Projects/climate_risk_report.json"

# File States
MOD_CSV_EXISTS="false"
MOD_CSV_SIZE=0
MOD_CSV_MODIFIED="false"

JSON_EXISTS="false"
JSON_SIZE=0
JSON_MODIFIED="false"

if [ -f "$MOD_CSV_FILE" ]; then
    MOD_CSV_EXISTS="true"
    MOD_CSV_SIZE=$(stat -c%s "$MOD_CSV_FILE" 2>/dev/null || echo "0")
    MOD_MTIME=$(stat -c%Y "$MOD_CSV_FILE" 2>/dev/null || echo "0")
    if [ "$MOD_MTIME" -gt "$TASK_START" ]; then
        MOD_CSV_MODIFIED="true"
    fi
fi

if [ -f "$JSON_FILE" ]; then
    JSON_EXISTS="true"
    JSON_SIZE=$(stat -c%s "$JSON_FILE" 2>/dev/null || echo "0")
    JSON_MTIME=$(stat -c%Y "$JSON_FILE" 2>/dev/null || echo "0")
    if [ "$JSON_MTIME" -gt "$TASK_START" ]; then
        JSON_MODIFIED="true"
    fi
fi

# Extract JSON values safely
BASELINE_KWH="0"
WARMED_KWH="0"
LOSS_KWH="0"
LOSS_PCT="0"

if [ -f "$JSON_FILE" ] && command -v jq &> /dev/null; then
    if jq empty "$JSON_FILE" 2>/dev/null; then
        BASELINE_KWH=$(jq -r '.baseline_energy_kwh // "0"' "$JSON_FILE" 2>/dev/null || echo "0")
        WARMED_KWH=$(jq -r '.warming_scenario_energy_kwh // "0"' "$JSON_FILE" 2>/dev/null || echo "0")
        LOSS_KWH=$(jq -r '.energy_loss_kwh // "0"' "$JSON_FILE" 2>/dev/null || echo "0")
        LOSS_PCT=$(jq -r '.percentage_loss_pct // "0"' "$JSON_FILE" 2>/dev/null || echo "0")
    fi
fi

# Build JSON payload
jq -n \
    --argjson python_ran "$PYTHON_RAN" \
    --argjson mod_csv_exists "$MOD_CSV_EXISTS" \
    --argjson mod_csv_size "$MOD_CSV_SIZE" \
    --argjson mod_csv_modified "$MOD_CSV_MODIFIED" \
    --argjson json_exists "$JSON_EXISTS" \
    --argjson json_size "$JSON_SIZE" \
    --argjson json_modified "$JSON_MODIFIED" \
    --arg baseline_kwh "$BASELINE_KWH" \
    --arg warmed_kwh "$WARMED_KWH" \
    --arg loss_kwh "$LOSS_KWH" \
    --arg loss_pct "$LOSS_PCT" \
    --arg timestamp "$(date -Iseconds)" \
    '{
        python_ran: $python_ran,
        mod_csv_exists: $mod_csv_exists,
        mod_csv_size: $mod_csv_size,
        mod_csv_modified: $mod_csv_modified,
        json_exists: $json_exists,
        json_size: $json_size,
        json_modified: $json_modified,
        baseline_kwh: $baseline_kwh,
        warmed_kwh: $warmed_kwh,
        loss_kwh: $loss_kwh,
        loss_pct: $loss_pct,
        timestamp: $timestamp
    }' > /tmp/task_result.json

chmod 666 /tmp/task_result.json 2>/dev/null || true

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="