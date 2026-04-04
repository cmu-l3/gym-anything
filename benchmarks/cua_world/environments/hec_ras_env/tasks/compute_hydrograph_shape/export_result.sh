#!/bin/bash
echo "=== Exporting hydrograph shape results ==="

source /workspace/scripts/task_utils.sh

# 1. Take final screenshot
take_screenshot /tmp/task_final.png

# 2. Collect file status
CSV_PATH="/home/ga/Documents/hec_ras_results/hydrograph_shape_params.csv"
SUMMARY_PATH="/home/ga/Documents/hec_ras_results/hydrograph_shape_summary.txt"
REF_PATH="/tmp/hydrograph_shape_reference.json"

TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
CSV_EXISTS="false"
CSV_MODIFIED="false"
SUMMARY_EXISTS="false"
SUMMARY_MODIFIED="false"

if [ -f "$CSV_PATH" ]; then
    CSV_EXISTS="true"
    MTIME=$(stat -c %Y "$CSV_PATH")
    if [ "$MTIME" -gt "$TASK_START" ]; then
        CSV_MODIFIED="true"
    fi
fi

if [ -f "$SUMMARY_PATH" ]; then
    SUMMARY_EXISTS="true"
    MTIME=$(stat -c %Y "$SUMMARY_PATH")
    if [ "$MTIME" -gt "$TASK_START" ]; then
        SUMMARY_MODIFIED="true"
    fi
fi

# 3. Create result JSON (to bundle metadata)
cat > /tmp/task_result.json << EOF
{
    "csv_exists": $CSV_EXISTS,
    "csv_modified": $CSV_MODIFIED,
    "summary_exists": $SUMMARY_EXISTS,
    "summary_modified": $SUMMARY_MODIFIED,
    "task_start_time": $TASK_START,
    "timestamp": "$(date -Iseconds)"
}
EOF

# 4. Ensure files are readable for the verifier (via copy_from_env)
chmod 644 /tmp/task_result.json 2>/dev/null || true
if [ -f "$CSV_PATH" ]; then chmod 644 "$CSV_PATH"; fi
if [ -f "$SUMMARY_PATH" ]; then chmod 644 "$SUMMARY_PATH"; fi
if [ -f "$REF_PATH" ]; then chmod 644 "$REF_PATH"; fi

# 5. Copy user files to tmp for easier extraction if paths are complex
# (Verifier will just pull from original paths, but this is a safety step)
if [ -f "$CSV_PATH" ]; then cp "$CSV_PATH" /tmp/agent_output.csv; fi
if [ -f "$SUMMARY_PATH" ]; then cp "$SUMMARY_PATH" /tmp/agent_summary.txt; fi

echo "Export complete. Result JSON at /tmp/task_result.json"