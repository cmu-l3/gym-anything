#!/bin/bash
echo "=== Exporting task results ==="

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Take final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# Target output files
CONSENSUS_PATH="/home/ga/UGENE_Data/16s_assembly/results/16s_consensus.fasta"
REPORT_PATH="/home/ga/UGENE_Data/16s_assembly/results/assembly_report.txt"

CONSENSUS_EXISTS="false"
CONSENSUS_CREATED="false"
REPORT_EXISTS="false"
REPORT_CREATED="false"

# Check Consensus FASTA
if [ -f "$CONSENSUS_PATH" ]; then
    CONSENSUS_EXISTS="true"
    MTIME=$(stat -c %Y "$CONSENSUS_PATH" 2>/dev/null || echo "0")
    if [ "$MTIME" -gt "$TASK_START" ]; then
        CONSENSUS_CREATED="true"
    fi
fi

# Check Report
if [ -f "$REPORT_PATH" ]; then
    REPORT_EXISTS="true"
    MTIME=$(stat -c %Y "$REPORT_PATH" 2>/dev/null || echo "0")
    if [ "$MTIME" -gt "$TASK_START" ]; then
        REPORT_CREATED="true"
    fi
fi

# Build result JSON for the Python verifier
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "consensus_exists": $CONSENSUS_EXISTS,
    "consensus_created_during_task": $CONSENSUS_CREATED,
    "report_exists": $REPORT_EXISTS,
    "report_created_during_task": $REPORT_CREATED
}
EOF

# Use safe move to avoid permission issues
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Results exported."
echo "=== Export complete ==="