#!/bin/bash
echo "=== Exporting task result ==="

# Take final screenshot
DISPLAY=:1 import -window root /tmp/task_final.png 2>/dev/null || true

TASK_START=$(cat /home/ga/.task_start_time 2>/dev/null || echo "0")

# Identify python script
SCRIPT_FILE="/home/ga/Documents/SAM_Projects/ramp_analysis_script.py"
SCRIPT_EXISTS="false"
SCRIPT_MODIFIED="false"
PYSAM_USED="false"

if [ -f "$SCRIPT_FILE" ]; then
    SCRIPT_EXISTS="true"
    if [ "$(stat -c%Y "$SCRIPT_FILE" 2>/dev/null || echo "0")" -gt "$TASK_START" ]; then
        SCRIPT_MODIFIED="true"
    fi
    if grep -ql "import PySAM\|from PySAM\|import Pvwatts\|Pvwattsv" "$SCRIPT_FILE" 2>/dev/null; then
        PYSAM_USED="true"
    fi
else
    # Fallback to check if they saved it elsewhere
    ALT_SCRIPT=$(find /home/ga -name "*.py" -newer /home/ga/.task_start_time 2>/dev/null | head -1)
    if [ -n "$ALT_SCRIPT" ]; then
        SCRIPT_EXISTS="true"
        SCRIPT_MODIFIED="true"
        SCRIPT_FILE="$ALT_SCRIPT"
        if grep -ql "import PySAM\|from PySAM\|import Pvwatts\|Pvwattsv" "$ALT_SCRIPT" 2>/dev/null; then
            PYSAM_USED="true"
        fi
    fi
fi

# Check for output JSON
JSON_FILE="/home/ga/Documents/SAM_Projects/ramp_rate_analysis.json"
JSON_EXISTS="false"
JSON_MODIFIED="false"

if [ -f "$JSON_FILE" ]; then
    JSON_EXISTS="true"
    if [ "$(stat -c%Y "$JSON_FILE" 2>/dev/null || echo "0")" -gt "$TASK_START" ]; then
        JSON_MODIFIED="true"
    fi
fi

# Create JSON result securely via jq
jq -n \
    --argjson script_exists "$SCRIPT_EXISTS" \
    --argjson script_modified "$SCRIPT_MODIFIED" \
    --argjson pysam_used "$PYSAM_USED" \
    --arg script_path "$SCRIPT_FILE" \
    --argjson json_exists "$JSON_EXISTS" \
    --argjson json_modified "$JSON_MODIFIED" \
    --arg json_path "$JSON_FILE" \
    --arg timestamp "$(date -Iseconds)" \
    '{
        script_exists: $script_exists,
        script_modified: $script_modified,
        pysam_used: $pysam_used,
        script_path: $script_path,
        json_exists: $json_exists,
        json_modified: $json_modified,
        json_path: $json_path,
        timestamp: $timestamp
    }' > /tmp/task_result.json

chmod 666 /tmp/task_result.json 2>/dev/null || true

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="