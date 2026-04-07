#!/bin/bash
echo "=== Exporting task result ==="

# Take final screenshot
DISPLAY=:1 import -window root /tmp/task_final.png 2>/dev/null || true

TASK_START=$(cat /home/ga/.task_start_time 2>/dev/null || echo "0")

# 1. Check Python Script Evidence
SCRIPT_FILE="/home/ga/Documents/SAM_Projects/outage_analysis.py"
SCRIPT_EXISTS="false"
USED_ADJ_FACTORS="false"
USED_PYSAM="false"

if [ -f "$SCRIPT_FILE" ]; then
    SCRIPT_EXISTS="true"
    if grep -qi "AdjustmentFactors" "$SCRIPT_FILE" 2>/dev/null; then
        USED_ADJ_FACTORS="true"
    fi
    if grep -qi "PySAM" "$SCRIPT_FILE" 2>/dev/null; then
        USED_PYSAM="true"
    fi
fi

# 2. Check JSON Results File
JSON_FILE="/home/ga/Documents/SAM_Projects/outage_results.json"
JSON_EXISTS="false"
JSON_MODIFIED="false"

if [ -f "$JSON_FILE" ]; then
    JSON_EXISTS="true"
    FILE_MTIME=$(stat -c%Y "$JSON_FILE" 2>/dev/null || echo "0")
    if [ "$FILE_MTIME" -gt "$TASK_START" ]; then
        JSON_MODIFIED="true"
    fi
fi

# 3. Extract Values from JSON
BASELINE_KWH="0"
SUMMER_KWH="0"
WINTER_KWH="0"
SUMMER_LOST="0"
WINTER_LOST="0"
RECOMMENDED=""

if [ -f "$JSON_FILE" ] && command -v jq &> /dev/null; then
    if jq empty "$JSON_FILE" 2>/dev/null; then
        BASELINE_KWH=$(jq -r '.baseline_energy_kwh // "0"' "$JSON_FILE" 2>/dev/null || echo "0")
        SUMMER_KWH=$(jq -r '.summer_outage_energy_kwh // "0"' "$JSON_FILE" 2>/dev/null || echo "0")
        WINTER_KWH=$(jq -r '.winter_outage_energy_kwh // "0"' "$JSON_FILE" 2>/dev/null || echo "0")
        SUMMER_LOST=$(jq -r '.summer_lost_revenue_dollars // "0"' "$JSON_FILE" 2>/dev/null || echo "0")
        WINTER_LOST=$(jq -r '.winter_lost_revenue_dollars // "0"' "$JSON_FILE" 2>/dev/null || echo "0")
        RECOMMENDED=$(jq -r '.recommended_outage_season // ""' "$JSON_FILE" 2>/dev/null || echo "")
    fi
fi

# 4. Create Export JSON
jq -n \
    --argjson script_exists "$SCRIPT_EXISTS" \
    --argjson used_adj_factors "$USED_ADJ_FACTORS" \
    --argjson used_pysam "$USED_PYSAM" \
    --argjson json_exists "$JSON_EXISTS" \
    --argjson json_modified "$JSON_MODIFIED" \
    --arg baseline_kwh "$BASELINE_KWH" \
    --arg summer_kwh "$SUMMER_KWH" \
    --arg winter_kwh "$WINTER_KWH" \
    --arg summer_lost "$SUMMER_LOST" \
    --arg winter_lost "$WINTER_LOST" \
    --arg recommended "$RECOMMENDED" \
    --arg timestamp "$(date -Iseconds)" \
    '{
        script_exists: $script_exists,
        used_adj_factors: $used_adj_factors,
        used_pysam: $used_pysam,
        json_exists: $json_exists,
        json_modified: $json_modified,
        baseline_kwh: $baseline_kwh,
        summer_kwh: $summer_kwh,
        winter_kwh: $winter_kwh,
        summer_lost: $summer_lost,
        winter_lost: $winter_lost,
        recommended: $recommended,
        timestamp: $timestamp
    }' > /tmp/task_result.json

chmod 666 /tmp/task_result.json 2>/dev/null || true

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="