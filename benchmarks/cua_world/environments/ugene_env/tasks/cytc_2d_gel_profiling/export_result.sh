#!/bin/bash
echo "=== Exporting cytc_2d_gel_profiling results ==="

TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
RESULTS_DIR="/home/ga/UGENE_Data/results"
CSV_FILE="${RESULTS_DIR}/cytc_2d_gel_profile.csv"
TXT_FILE="${RESULTS_DIR}/ief_strip_recommendation.txt"

# Take final screenshot
DISPLAY=:1 scrot /tmp/task_final_state.png 2>/dev/null || true

CSV_EXISTS="false"
CSV_CONTENT=""
CSV_CREATED_DURING_TASK="false"

TXT_EXISTS="false"
TXT_CONTENT=""
TXT_CREATED_DURING_TASK="false"

if [ -f "$CSV_FILE" ]; then
    CSV_EXISTS="true"
    CSV_CONTENT=$(cat "$CSV_FILE" | head -n 20)
    CSV_MTIME=$(stat -c %Y "$CSV_FILE" 2>/dev/null || echo "0")
    if [ "$CSV_MTIME" -ge "$TASK_START" ]; then
        CSV_CREATED_DURING_TASK="true"
    fi
fi

if [ -f "$TXT_FILE" ]; then
    TXT_EXISTS="true"
    TXT_CONTENT=$(cat "$TXT_FILE" | head -n 20)
    TXT_MTIME=$(stat -c %Y "$TXT_FILE" 2>/dev/null || echo "0")
    if [ "$TXT_MTIME" -ge "$TASK_START" ]; then
        TXT_CREATED_DURING_TASK="true"
    fi
fi

# Build JSON payload
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
python3 << PYEOF
import json

result = {
    "task_start": int("$TASK_START"),
    "csv_exists": "$CSV_EXISTS" == "true",
    "csv_created_during_task": "$CSV_CREATED_DURING_TASK" == "true",
    "csv_content": """$CSV_CONTENT""",
    "txt_exists": "$TXT_EXISTS" == "true",
    "txt_created_during_task": "$TXT_CREATED_DURING_TASK" == "true",
    "txt_content": """$TXT_CONTENT"""
}

with open("$TEMP_JSON", "w") as f:
    json.dump(result, f, indent=2)
PYEOF

rm -f /tmp/cytc_2d_gel_profiling_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/cytc_2d_gel_profiling_result.json 2>/dev/null || true
chmod 666 /tmp/cytc_2d_gel_profiling_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Results exported to /tmp/cytc_2d_gel_profiling_result.json"
cat /tmp/cytc_2d_gel_profiling_result.json
echo "=== Export complete ==="