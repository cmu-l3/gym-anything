#!/bin/bash
echo "=== Exporting task result ==="

# Take final screenshot
DISPLAY=:1 import -window root /tmp/task_end.png 2>/dev/null || true

TASK_START=$(cat /home/ga/.task_start_time 2>/dev/null || echo "0")
EVIDENCE_FOUND="false"

# Check if any .py or .sam files were created/modified as evidence
EVIDENCE_FILES=$(find /home/ga/Documents/SAM_Projects -type f \( -name "*.py" -o -name "*.sam" \) -newer /home/ga/.task_start_time 2>/dev/null)
if [ -n "$EVIDENCE_FILES" ]; then
    EVIDENCE_FOUND="true"
fi

# Check if expected JSON file exists
EXPECTED_FILE="/home/ga/Documents/SAM_Projects/snow_loss_analysis.json"

FILE_EXISTS="false"
FILE_SIZE=0
FILE_MODIFIED="false"

if [ -f "$EXPECTED_FILE" ]; then
    FILE_EXISTS="true"
    FILE_SIZE=$(stat -c%s "$EXPECTED_FILE" 2>/dev/null || echo "0")

    FILE_MTIME=$(stat -c%Y "$EXPECTED_FILE" 2>/dev/null || echo "0")
    if [ "$FILE_MTIME" -gt "$TASK_START" ]; then
        FILE_MODIFIED="true"
    fi
fi

# Extract JSON values safely using jq
BASELINE_KWH="0"
SNOW_MODEL_KWH="0"
SNOW_LOSS_KWH="0"
SNOW_LOSS_PCT="0"

if [ -f "$EXPECTED_FILE" ] && command -v jq &> /dev/null; then
    if jq empty "$EXPECTED_FILE" 2>/dev/null; then
        BASELINE_KWH=$(jq -r '.baseline_energy_kwh // 0' "$EXPECTED_FILE" 2>/dev/null || echo "0")
        SNOW_MODEL_KWH=$(jq -r '.snow_model_energy_kwh // 0' "$EXPECTED_FILE" 2>/dev/null || echo "0")
        SNOW_LOSS_KWH=$(jq -r '.snow_loss_kwh // 0' "$EXPECTED_FILE" 2>/dev/null || echo "0")
        SNOW_LOSS_PCT=$(jq -r '.snow_loss_percentage // 0' "$EXPECTED_FILE" 2>/dev/null || echo "0")
    fi
fi

# Create JSON result safely using jq
jq -n \
    --argjson file_exists "$FILE_EXISTS" \
    --argjson file_size "$FILE_SIZE" \
    --argjson file_modified "$FILE_MODIFIED" \
    --argjson evidence_found "$EVIDENCE_FOUND" \
    --arg baseline_kwh "$BASELINE_KWH" \
    --arg snow_model_kwh "$SNOW_MODEL_KWH" \
    --arg snow_loss_kwh "$SNOW_LOSS_KWH" \
    --arg snow_loss_pct "$SNOW_LOSS_PCT" \
    --arg timestamp "$(date -Iseconds)" \
    '{
        file_exists: $file_exists,
        file_size: $file_size,
        file_modified: $file_modified,
        evidence_found: $evidence_found,
        baseline_kwh: $baseline_kwh,
        snow_model_kwh: $snow_model_kwh,
        snow_loss_kwh: $snow_loss_kwh,
        snow_loss_pct: $snow_loss_pct,
        timestamp: $timestamp
    }' > /tmp/task_result.json

chmod 666 /tmp/task_result.json 2>/dev/null || true

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="