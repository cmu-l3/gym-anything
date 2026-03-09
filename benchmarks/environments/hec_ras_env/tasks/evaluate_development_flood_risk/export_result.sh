#!/bin/bash
echo "=== Exporting evaluate_development_flood_risk result ==="

# Source utils
source /workspace/scripts/task_utils.sh

# Paths
RESULTS_DIR="/home/ga/Documents/hec_ras_results"
OUTPUT_CSV="$RESULTS_DIR/site_risk_assessment.csv"
OUTPUT_TXT="$RESULTS_DIR/risk_summary.txt"
GROUND_TRUTH="/var/lib/hec_ras/ground_truth.csv"

# Take final screenshot
take_screenshot /tmp/task_final.png

# Check if output files exist
CSV_EXISTS="false"
TXT_EXISTS="false"
CSV_SIZE=0
TXT_SIZE=0

if [ -f "$OUTPUT_CSV" ]; then
    CSV_EXISTS="true"
    CSV_SIZE=$(stat -c %s "$OUTPUT_CSV")
fi

if [ -f "$OUTPUT_TXT" ]; then
    TXT_EXISTS="true"
    TXT_SIZE=$(stat -c %s "$OUTPUT_TXT")
fi

# Check timestamps vs task start
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
FILES_NEW="false"
if [ "$CSV_EXISTS" = "true" ]; then
    FILE_TIME=$(stat -c %Y "$OUTPUT_CSV")
    if [ "$FILE_TIME" -ge "$TASK_START" ]; then
        FILES_NEW="true"
    fi
fi

# Prepare result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "csv_exists": $CSV_EXISTS,
    "txt_exists": $TXT_EXISTS,
    "csv_size": $CSV_SIZE,
    "files_created_during_task": $FILES_NEW,
    "timestamp": $(date +%s)
}
EOF

# Move result JSON
mv "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json

# Copy files for verifier to access
# The verifier runs outside the container, so we need to put everything in a readable location
# or rely on the framework's copy_from_env mechanism to pull specific files.
# We will stage them in /tmp for easy retrieval.

if [ "$CSV_EXISTS" = "true" ]; then
    cp "$OUTPUT_CSV" /tmp/agent_output.csv
    chmod 666 /tmp/agent_output.csv
fi

if [ "$TXT_EXISTS" = "true" ]; then
    cp "$OUTPUT_TXT" /tmp/agent_summary.txt
    chmod 666 /tmp/agent_summary.txt
fi

if [ -f "$GROUND_TRUTH" ]; then
    cp "$GROUND_TRUTH" /tmp/ground_truth_export.csv
    chmod 666 /tmp/ground_truth_export.csv
fi

echo "Export complete. Result JSON and staged files ready in /tmp."