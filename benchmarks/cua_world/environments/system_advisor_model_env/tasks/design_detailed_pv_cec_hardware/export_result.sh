#!/bin/bash
echo "=== Exporting task result ==="

TASK_START=$(cat /home/ga/.task_start_time 2>/dev/null || echo "0")

# Take final screenshot
DISPLAY=:1 import -window root /tmp/task_final.png 2>/dev/null || true

# Define target files
SAM_FILE="/home/ga/Documents/SAM_Projects/detailed_hardware_design.sam"
JSON_FILE="/home/ga/Documents/SAM_Projects/design_summary.json"

# Check SAM File
SAM_EXISTS="false"
SAM_MODIFIED="false"
SAM_PVSAMV1="false"
SAM_CANADIAN="false"
SAM_SMA="false"

if [ -f "$SAM_FILE" ]; then
    SAM_EXISTS="true"
    SAM_MTIME=$(stat -c%Y "$SAM_FILE" 2>/dev/null || echo "0")
    if [ "$SAM_MTIME" -gt "$TASK_START" ]; then
        SAM_MODIFIED="true"
    fi
    
    # Use strings to safely grep binary or text SAM files
    if strings "$SAM_FILE" | grep -qi "pvsamv1"; then
        SAM_PVSAMV1="true"
    fi
    if strings "$SAM_FILE" | grep -qi "Canadian Solar"; then
        SAM_CANADIAN="true"
    fi
    if strings "$SAM_FILE" | grep -qi "SMA"; then
        SAM_SMA="true"
    fi
fi

# Check JSON File
JSON_EXISTS="false"
JSON_MODIFIED="false"
MODULE_SELECTED=""
INVERTER_SELECTED=""
DC_CAPACITY="0"
INVERTER_COUNT="0"

if [ -f "$JSON_FILE" ]; then
    JSON_EXISTS="true"
    JSON_MTIME=$(stat -c%Y "$JSON_FILE" 2>/dev/null || echo "0")
    if [ "$JSON_MTIME" -gt "$TASK_START" ]; then
        JSON_MODIFIED="true"
    fi
    
    if command -v jq &> /dev/null; then
        MODULE_SELECTED=$(jq -r '.module_selected // empty' "$JSON_FILE" 2>/dev/null || echo "")
        INVERTER_SELECTED=$(jq -r '.inverter_selected // empty' "$JSON_FILE" 2>/dev/null || echo "")
        DC_CAPACITY=$(jq -r '.total_dc_capacity_kw // "0"' "$JSON_FILE" 2>/dev/null || echo "0")
        INVERTER_COUNT=$(jq -r '.inverter_count // "0"' "$JSON_FILE" 2>/dev/null || echo "0")
    else
        # Fallback if jq is not available
        MODULE_SELECTED=$(grep -oP '"module_selected"\s*:\s*"\K[^"]+' "$JSON_FILE" || echo "")
        INVERTER_SELECTED=$(grep -oP '"inverter_selected"\s*:\s*"\K[^"]+' "$JSON_FILE" || echo "")
        DC_CAPACITY=$(grep -oP '"total_dc_capacity_kw"\s*:\s*\K[0-9.]+' "$JSON_FILE" || echo "0")
        INVERTER_COUNT=$(grep -oP '"inverter_count"\s*:\s*\K[0-9]+' "$JSON_FILE" || echo "0")
    fi
fi

# Check if SAM is actually running
SAM_RUNNING=$(pgrep -f "sam" > /dev/null || pgrep -f "SAM" > /dev/null && echo "true" || echo "false")

# Create JSON result safely using jq
jq -n \
    --argjson sam_exists "$SAM_EXISTS" \
    --argjson sam_modified "$SAM_MODIFIED" \
    --argjson sam_pvsamv1 "$SAM_PVSAMV1" \
    --argjson sam_canadian "$SAM_CANADIAN" \
    --argjson sam_sma "$SAM_SMA" \
    --argjson json_exists "$JSON_EXISTS" \
    --argjson json_modified "$JSON_MODIFIED" \
    --arg module_selected "$MODULE_SELECTED" \
    --arg inverter_selected "$INVERTER_SELECTED" \
    --arg dc_capacity "$DC_CAPACITY" \
    --arg inverter_count "$INVERTER_COUNT" \
    --argjson sam_running "$SAM_RUNNING" \
    --arg timestamp "$(date -Iseconds)" \
    '{
        sam_exists: $sam_exists,
        sam_modified: $sam_modified,
        sam_pvsamv1: $sam_pvsamv1,
        sam_canadian: $sam_canadian,
        sam_sma: $sam_sma,
        json_exists: $json_exists,
        json_modified: $json_modified,
        module_selected: $module_selected,
        inverter_selected: $inverter_selected,
        dc_capacity: $dc_capacity,
        inverter_count: $inverter_count,
        sam_running: $sam_running,
        timestamp: $timestamp
    }' > /tmp/task_result.json

chmod 666 /tmp/task_result.json 2>/dev/null || true

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="