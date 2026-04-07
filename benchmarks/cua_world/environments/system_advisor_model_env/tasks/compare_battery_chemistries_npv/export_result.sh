#!/bin/bash
echo "=== Exporting task result ==="

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /home/ga/.task_start_time 2>/dev/null || echo "0")

# Take final screenshot
DISPLAY=:1 import -window root /tmp/task_final.png 2>/dev/null || true

# Check for the expected artifact file (.sam or .py)
ARTIFACT_EXISTS="false"
ARTIFACT_MODIFIED="false"
ARTIFACT_PATH=""

if [ -f "/home/ga/Documents/SAM_Projects/battery_comparison.sam" ]; then
    ARTIFACT_EXISTS="true"
    ARTIFACT_PATH="/home/ga/Documents/SAM_Projects/battery_comparison.sam"
elif [ -f "/home/ga/Documents/SAM_Projects/compare_batteries.py" ]; then
    ARTIFACT_EXISTS="true"
    ARTIFACT_PATH="/home/ga/Documents/SAM_Projects/compare_batteries.py"
fi

if [ "$ARTIFACT_EXISTS" = "true" ]; then
    FILE_MTIME=$(stat -c%Y "$ARTIFACT_PATH" 2>/dev/null || echo "0")
    if [ "$FILE_MTIME" -gt "$TASK_START" ]; then
        ARTIFACT_MODIFIED="true"
    fi
fi

# Check for the JSON results file
JSON_FILE="/home/ga/Documents/SAM_Projects/battery_chemistry_comparison.json"
JSON_EXISTS="false"
JSON_MODIFIED="false"

if [ -f "$JSON_FILE" ]; then
    JSON_EXISTS="true"
    FILE_MTIME=$(stat -c%Y "$JSON_FILE" 2>/dev/null || echo "0")
    if [ "$FILE_MTIME" -gt "$TASK_START" ]; then
        JSON_MODIFIED="true"
    fi
fi

# Extract JSON parameters
SYSTEM_SIZE="0"
BATTERY_CAPACITY="0"
LA_NPV="0"
LA_REP_COST="0"
LFP_NPV="0"
LFP_REP_COST="0"

if [ "$JSON_EXISTS" = "true" ] && command -v jq &> /dev/null; then
    if jq empty "$JSON_FILE" 2>/dev/null; then
        SYSTEM_SIZE=$(jq -r '.system_size_kw // 0' "$JSON_FILE" 2>/dev/null || echo "0")
        BATTERY_CAPACITY=$(jq -r '.battery_capacity_kwh // 0' "$JSON_FILE" 2>/dev/null || echo "0")
        
        LA_NPV=$(jq -r '.scenarios.lead_acid.npv_dollars // 0' "$JSON_FILE" 2>/dev/null || echo "0")
        LA_REP_COST=$(jq -r '.scenarios.lead_acid.pv_battery_replacement_cost_dollars // 0' "$JSON_FILE" 2>/dev/null || echo "0")
        
        LFP_NPV=$(jq -r '.scenarios.lithium_ion_lfp.npv_dollars // 0' "$JSON_FILE" 2>/dev/null || echo "0")
        LFP_REP_COST=$(jq -r '.scenarios.lithium_ion_lfp.pv_battery_replacement_cost_dollars // 0' "$JSON_FILE" 2>/dev/null || echo "0")
    fi
fi

# Create export JSON safely
jq -n \
    --argjson artifact_exists "$ARTIFACT_EXISTS" \
    --argjson artifact_modified "$ARTIFACT_MODIFIED" \
    --arg artifact_path "$ARTIFACT_PATH" \
    --argjson json_exists "$JSON_EXISTS" \
    --argjson json_modified "$JSON_MODIFIED" \
    --arg system_size "$SYSTEM_SIZE" \
    --arg battery_capacity "$BATTERY_CAPACITY" \
    --arg la_npv "$LA_NPV" \
    --arg la_rep_cost "$LA_REP_COST" \
    --arg lfp_npv "$LFP_NPV" \
    --arg lfp_rep_cost "$LFP_REP_COST" \
    --arg timestamp "$(date -Iseconds)" \
    '{
        artifact_exists: $artifact_exists,
        artifact_modified: $artifact_modified,
        artifact_path: $artifact_path,
        json_exists: $json_exists,
        json_modified: $json_modified,
        system_size: $system_size,
        battery_capacity: $battery_capacity,
        la_npv: $la_npv,
        la_rep_cost: $la_rep_cost,
        lfp_npv: $lfp_npv,
        lfp_rep_cost: $lfp_rep_cost,
        timestamp: $timestamp
    }' > /tmp/task_result.json

chmod 666 /tmp/task_result.json 2>/dev/null || true

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="