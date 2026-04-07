#!/bin/bash
set -e
echo "=== Exporting insulin_orf_protein_analysis results ==="

# Record task times
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

RESULTS_DIR="/home/ga/UGENE_Data/results"
FASTA_FILE="${RESULTS_DIR}/insulin_protein.fa"
GB_FILE="${RESULTS_DIR}/insulin_annotated.gb"
REPORT_FILE="${RESULTS_DIR}/insulin_characterization.txt"

# Take final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# Initialize tracking variables
FASTA_EXISTS="false"
GB_EXISTS="false"
REPORT_EXISTS="false"
FILES_CREATED_DURING_TASK="false"
FASTA_SIZE=0
GB_SIZE=0
REPORT_SIZE=0

# Check FASTA
if [ -f "$FASTA_FILE" ]; then
    FASTA_EXISTS="true"
    FASTA_SIZE=$(stat -c %s "$FASTA_FILE" 2>/dev/null || echo "0")
    MTIME=$(stat -c %Y "$FASTA_FILE" 2>/dev/null || echo "0")
    if [ "$MTIME" -gt "$TASK_START" ]; then FILES_CREATED_DURING_TASK="true"; fi
    
    # Copy to tmp for verifier
    cp "$FASTA_FILE" /tmp/insulin_protein.fa 2>/dev/null || true
    chmod 666 /tmp/insulin_protein.fa 2>/dev/null || true
fi

# Check GenBank
if [ -f "$GB_FILE" ]; then
    GB_EXISTS="true"
    GB_SIZE=$(stat -c %s "$GB_FILE" 2>/dev/null || echo "0")
    MTIME=$(stat -c %Y "$GB_FILE" 2>/dev/null || echo "0")
    if [ "$MTIME" -gt "$TASK_START" ]; then FILES_CREATED_DURING_TASK="true"; fi
    
    # Copy to tmp for verifier
    cp "$GB_FILE" /tmp/insulin_annotated.gb 2>/dev/null || true
    chmod 666 /tmp/insulin_annotated.gb 2>/dev/null || true
fi

# Check Report
if [ -f "$REPORT_FILE" ]; then
    REPORT_EXISTS="true"
    REPORT_SIZE=$(stat -c %s "$REPORT_FILE" 2>/dev/null || echo "0")
    MTIME=$(stat -c %Y "$REPORT_FILE" 2>/dev/null || echo "0")
    if [ "$MTIME" -gt "$TASK_START" ]; then FILES_CREATED_DURING_TASK="true"; fi
    
    # Copy to tmp for verifier
    cp "$REPORT_FILE" /tmp/insulin_characterization.txt 2>/dev/null || true
    chmod 666 /tmp/insulin_characterization.txt 2>/dev/null || true
fi

# Check if UGENE was running
UGENE_RUNNING=$(pgrep -f "ugene" > /dev/null && echo "true" || echo "false")

# Create JSON result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "fasta_exists": $FASTA_EXISTS,
    "gb_exists": $GB_EXISTS,
    "report_exists": $REPORT_EXISTS,
    "fasta_size": $FASTA_SIZE,
    "gb_size": $GB_SIZE,
    "report_size": $REPORT_SIZE,
    "files_created_during_task": $FILES_CREATED_DURING_TASK,
    "ugene_was_running": $UGENE_RUNNING,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move JSON to final location safely
rm -f /tmp/insulin_task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/insulin_task_result.json 2>/dev/null
chmod 666 /tmp/insulin_task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Exported task result successfully."
cat /tmp/insulin_task_result.json
echo "=== Export complete ==="