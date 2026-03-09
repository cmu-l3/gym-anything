#!/bin/bash
echo "=== Exporting task results ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Paths
REF_FILE="/home/ga/shortcuts_reference.txt"
EVIDENCE_IMG="/home/ga/shortcuts_evidence.png"

# Check Reference File
REF_EXISTS="false"
REF_CREATED_DURING="false"
REF_CONTENT=""
if [ -f "$REF_FILE" ]; then
    REF_EXISTS="true"
    REF_MTIME=$(stat -c %Y "$REF_FILE" 2>/dev/null || echo "0")
    if [ "$REF_MTIME" -gt "$TASK_START" ]; then
        REF_CREATED_DURING="true"
    fi
    # Read content (limit size to avoid huge logs)
    REF_CONTENT=$(head -c 1000 "$REF_FILE" | base64 -w 0)
fi

# Check Evidence Screenshot
EVIDENCE_EXISTS="false"
EVIDENCE_CREATED_DURING="false"
if [ -f "$EVIDENCE_IMG" ]; then
    EVIDENCE_EXISTS="true"
    EVIDENCE_MTIME=$(stat -c %Y "$EVIDENCE_IMG" 2>/dev/null || echo "0")
    if [ "$EVIDENCE_MTIME" -gt "$TASK_START" ]; then
        EVIDENCE_CREATED_DURING="true"
    fi
fi

# Check if Firefox is still running and url (proxy for still being in meeting)
APP_RUNNING=$(pgrep -f "firefox" > /dev/null && echo "true" || echo "false")

# Take final screenshot for VLM verification of end state
take_screenshot /tmp/task_final.png

# Create JSON result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "ref_file_exists": $REF_EXISTS,
    "ref_file_created_during_task": $REF_CREATED_DURING,
    "ref_file_content_b64": "$REF_CONTENT",
    "evidence_img_exists": $EVIDENCE_EXISTS,
    "evidence_img_created_during_task": $EVIDENCE_CREATED_DURING,
    "app_running": $APP_RUNNING
}
EOF

# Move to standard location
mv "$TEMP_JSON" /tmp/task_result.json
chmod 644 /tmp/task_result.json

# If evidence image exists, copy it to a temp location for the verifier to access easily if needed
if [ -f "$EVIDENCE_IMG" ]; then
    cp "$EVIDENCE_IMG" /tmp/verifier_evidence.png
    chmod 644 /tmp/verifier_evidence.png
fi

echo "Result exported to /tmp/task_result.json"