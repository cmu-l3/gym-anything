#!/bin/bash
echo "=== Exporting task result ==="

# Take final screenshot
DISPLAY=:1 import -window root /tmp/task_end.png 2>/dev/null || true

TASK_START=$(cat /home/ga/.task_start_time 2>/dev/null || echo "0")

# Anti-bypass: Check if Python was actually used during the task
PYTHON_RAN="false"
if [ -f /home/ga/.bash_history ]; then
    if grep -q "python3\|python " /home/ga/.bash_history 2>/dev/null; then
        PYTHON_RAN="true"
    fi
fi

# Check for .sam file
SAM_FILE="/home/ga/Documents/SAM_Projects/ac_vs_dc_bess.sam"
SAM_EXISTS="false"
SAM_MODIFIED="false"
SAM_SIZE=0

if [ -f "$SAM_FILE" ]; then
    SAM_EXISTS="true"
    SAM_SIZE=$(stat -c%s "$SAM_FILE" 2>/dev/null || echo "0")
    SAM_MTIME=$(stat -c%Y "$SAM_FILE" 2>/dev/null || echo "0")
    if [ "$SAM_MTIME" -gt "$TASK_START" ]; then
        SAM_MODIFIED="true"
    fi
fi

# Check for results json file
JSON_FILE="/home/ga/Documents/SAM_Projects/bess_results.json"
JSON_EXISTS="false"
JSON_MODIFIED="false"
JSON_SIZE=0

if [ -f "$JSON_FILE" ]; then
    JSON_EXISTS="true"
    JSON_SIZE=$(stat -c%s "$JSON_FILE" 2>/dev/null || echo "0")
    JSON_MTIME=$(stat -c%Y "$JSON_FILE" 2>/dev/null || echo "0")
    if [ "$JSON_MTIME" -gt "$TASK_START" ]; then
        JSON_MODIFIED="true"
    fi
fi

# Parse JSON values safely using jq
AC_ENERGY="0"
AC_NPV="0"
DC_ENERGY="0"
DC_NPV="0"
HAS_KEYS="false"

if [ "$JSON_EXISTS" = "true" ] && command -v jq &> /dev/null; then
    if jq empty "$JSON_FILE" 2>/dev/null; then
        AC_ENERGY=$(jq -r '.ac_coupled.annual_energy_kwh // "0"' "$JSON_FILE" 2>/dev/null || echo "0")
        AC_NPV=$(jq -r '.ac_coupled.npv_dollars // "0"' "$JSON_FILE" 2>/dev/null || echo "0")
        DC_ENERGY=$(jq -r '.dc_coupled.annual_energy_kwh // "0"' "$JSON_FILE" 2>/dev/null || echo "0")
        DC_NPV=$(jq -r '.dc_coupled.npv_dollars // "0"' "$JSON_FILE" 2>/dev/null || echo "0")

        HAS_AC=$(jq -r 'has("ac_coupled")' "$JSON_FILE" 2>/dev/null || echo "false")
        HAS_DC=$(jq -r 'has("dc_coupled")' "$JSON_FILE" 2>/dev/null || echo "false")
        if [ "$HAS_AC" = "true" ] && [ "$HAS_DC" = "true" ]; then
            HAS_KEYS="true"
        fi
    fi
fi

# Output JSON securely
jq -n \
    --argjson sam_exists "$SAM_EXISTS" \
    --argjson sam_size "$SAM_SIZE" \
    --argjson sam_modified "$SAM_MODIFIED" \
    --argjson json_exists "$JSON_EXISTS" \
    --argjson json_size "$JSON_SIZE" \
    --argjson json_modified "$JSON_MODIFIED" \
    --argjson python_ran "$PYTHON_RAN" \
    --arg ac_energy "$AC_ENERGY" \
    --arg ac_npv "$AC_NPV" \
    --arg dc_energy "$DC_ENERGY" \
    --arg dc_npv "$DC_NPV" \
    --argjson has_keys "$HAS_KEYS" \
    --arg timestamp "$(date -Iseconds)" \
    '{
        sam_exists: $sam_exists,
        sam_size: $sam_size,
        sam_modified: $sam_modified,
        json_exists: $json_exists,
        json_size: $json_size,
        json_modified: $json_modified,
        python_ran: $python_ran,
        ac_energy: $ac_energy,
        ac_npv: $ac_npv,
        dc_energy: $dc_energy,
        dc_npv: $dc_npv,
        has_keys: $has_keys,
        timestamp: $timestamp
    }' > /tmp/task_result.json

chmod 666 /tmp/task_result.json 2>/dev/null || true

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="