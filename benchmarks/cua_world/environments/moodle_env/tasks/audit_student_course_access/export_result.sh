#!/bin/bash
# Export script for Audit Student Course Access

echo "=== Exporting Audit Results ==="

# Define paths
EVIDENCE_PATH="/home/ga/Documents/audit_evidence.xlsx"
VERDICT_PATH="/home/ga/Documents/verdict.txt"
TASK_START=$(cat /tmp/task_start_timestamp 2>/dev/null || echo "0")
NOW=$(date +%s)

# Take screenshot
DISPLAY=:1 scrot /tmp/task_end_screenshot.png 2>/dev/null || true

# Check Evidence File
EVIDENCE_EXISTS="false"
EVIDENCE_SIZE="0"
EVIDENCE_CREATED_DURING="false"

if [ -f "$EVIDENCE_PATH" ]; then
    EVIDENCE_EXISTS="true"
    EVIDENCE_SIZE=$(stat -c %s "$EVIDENCE_PATH")
    FILE_MTIME=$(stat -c %Y "$EVIDENCE_PATH")
    if [ "$FILE_MTIME" -ge "$TASK_START" ]; then
        EVIDENCE_CREATED_DURING="true"
    fi
fi

# Check Verdict File
VERDICT_EXISTS="false"
VERDICT_CONTENT=""
VERDICT_CREATED_DURING="false"

if [ -f "$VERDICT_PATH" ]; then
    VERDICT_EXISTS="true"
    # Read first line, trim whitespace
    VERDICT_CONTENT=$(head -n 1 "$VERDICT_PATH" | xargs)
    FILE_MTIME=$(stat -c %Y "$VERDICT_PATH")
    if [ "$FILE_MTIME" -ge "$TASK_START" ]; then
        VERDICT_CREATED_DURING="true"
    fi
fi

# Copy files for verification
# We move them to /tmp with known names for the python verifier to pick up via copy_from_env
cp "$EVIDENCE_PATH" /tmp/verify_evidence.xlsx 2>/dev/null || true
chmod 666 /tmp/verify_evidence.xlsx 2>/dev/null || true

# JSON Result
TEMP_JSON=$(mktemp /tmp/audit_result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $NOW,
    "evidence_exists": $EVIDENCE_EXISTS,
    "evidence_size": $EVIDENCE_SIZE,
    "evidence_fresh": $EVIDENCE_CREATED_DURING,
    "verdict_exists": $VERDICT_EXISTS,
    "verdict_content": "$VERDICT_CONTENT",
    "verdict_fresh": $VERDICT_CREATED_DURING,
    "evidence_path_tmp": "/tmp/verify_evidence.xlsx"
}
EOF

# Safe move
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result exported to /tmp/task_result.json"
cat /tmp/task_result.json