#!/bin/bash
# Export result for posner_cueing_ior_analysis
# Stages the output file for the verifier and captures the final state.

set -e
echo "=== Exporting posner_cueing_ior_analysis result ==="

export DISPLAY=:1
export XAUTHORITY=/home/ga/.Xauthority

# Record task end time
TASK_START=$(cat /tmp/task_start_timestamp 2>/dev/null || echo "0")
TASK_END=$(date +%s)

# Take final screenshot for evidence
DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority scrot /tmp/task_final.png 2>/dev/null || true

OUTPUT_PATH="/home/ga/pebl/analysis/posner_ior_report.json"
FILE_EXISTS="false"
FILE_NEW="false"

if [ -f "$OUTPUT_PATH" ]; then
    FILE_EXISTS="true"
    cp "$OUTPUT_PATH" /tmp/posner_result.json
    chmod 644 /tmp/posner_result.json
    
    # Check if created during task
    FILE_MTIME=$(stat -c %Y "$OUTPUT_PATH" 2>/dev/null || echo "0")
    if [ "$FILE_MTIME" -ge "$TASK_START" ]; then
        FILE_NEW="true"
    fi
fi

# Write metadata for verifier
cat > /tmp/posner_meta.json << EOF
{
    "file_exists": $FILE_EXISTS,
    "file_created_during_task": $FILE_NEW
}
EOF
chmod 644 /tmp/posner_meta.json

echo "=== posner_cueing_ior_analysis export complete ==="