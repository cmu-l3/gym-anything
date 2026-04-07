#!/bin/bash
echo "=== Exporting compose_rich_text_newsletter result ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_final.png

# Paths
TB_PROFILE="/home/ga/.thunderbird/default-release"
DRAFTS_FILE="${TB_PROFILE}/Mail/Local Folders/Drafts"

DRAFTS_MTIME="0"
if [ -f "$DRAFTS_FILE" ]; then
    DRAFTS_MTIME=$(stat -c %Y "$DRAFTS_FILE" 2>/dev/null || echo "0")
    # Copy to a known temp location for the verifier to easily copy_from_env
    cp "$DRAFTS_FILE" /tmp/Drafts.mbox
    chmod 666 /tmp/Drafts.mbox
else
    # Create empty file so verifier doesn't crash on copy
    touch /tmp/Drafts.mbox
    chmod 666 /tmp/Drafts.mbox
fi

TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Create JSON containing task run data
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "drafts_mtime": $DRAFTS_MTIME
}
EOF

# Move to final location safely
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "=== Export complete ==="