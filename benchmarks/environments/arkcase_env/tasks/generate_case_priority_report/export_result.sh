#!/bin/bash
echo "=== Exporting generate_case_priority_report result ==="

# Source utils
source /workspace/scripts/task_utils.sh

TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
OUTPUT_FILE="/home/ga/priority_report.csv"
GROUND_TRUTH_FILE="/tmp/ground_truth.json"

# 1. Take final screenshot
take_screenshot /tmp/task_final.png

# 2. Check output file status
OUTPUT_EXISTS="false"
FILE_CREATED_DURING_TASK="false"
OUTPUT_SIZE=0

if [ -f "$OUTPUT_FILE" ]; then
    OUTPUT_EXISTS="true"
    OUTPUT_SIZE=$(stat -c %s "$OUTPUT_FILE")
    OUTPUT_MTIME=$(stat -c %Y "$OUTPUT_FILE")
    
    if [ "$OUTPUT_MTIME" -gt "$TASK_START" ]; then
        FILE_CREATED_DURING_TASK="true"
    fi
fi

# 3. Prepare data for verifier
# We package everything into a JSON result, but we also keep the raw files
# accessible for the Python verifier to copy.
# The verifier needs:
# - The agent's CSV
# - The ground truth JSON

# Create a temporary directory for export
EXPORT_DIR="/tmp/export_data"
mkdir -p "$EXPORT_DIR"
cp "$GROUND_TRUTH_FILE" "$EXPORT_DIR/ground_truth.json" 2>/dev/null || echo "[]" > "$EXPORT_DIR/ground_truth.json"

if [ "$OUTPUT_EXISTS" = "true" ]; then
    cp "$OUTPUT_FILE" "$EXPORT_DIR/agent_report.csv"
else
    touch "$EXPORT_DIR/agent_report.csv" # Empty file if not exists
fi

# Create metadata JSON for the verifier
cat <<EOF > "$EXPORT_DIR/metadata.json"
{
    "task_start": $TASK_START,
    "file_created_during_task": $FILE_CREATED_DURING_TASK,
    "output_exists": $OUTPUT_EXISTS,
    "output_path": "$OUTPUT_FILE"
}
EOF

# Compress export data for easy retrieval by verifier
# (Simpler strategy: just leave them in /tmp/export_data and verifier copies individual files)

echo "=== Export complete ==="
ls -l "$EXPORT_DIR"