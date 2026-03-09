#!/bin/bash
echo "=== Exporting patch_recovery_operation results ==="

source /workspace/scripts/task_utils.sh

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Take final screenshot
take_screenshot /tmp/task_final.png

# 1. CHECK FILESYSTEM OUTPUTS (Extracted Patches)
OUTPUT_DIR="/home/ga/Documents/patches"
FILES_CREATED=0
VALID_CONTENT_FILES=0

if [ -d "$OUTPUT_DIR" ]; then
    # List files created after task start
    # Note: Using find -newer is safer than simple ls
    touch -t $(date -d @$TASK_START +%Y%m%d%H%M.%S) /tmp/start_ref
    
    for f in "$OUTPUT_DIR"/*; do
        if [ -f "$f" ] && [ "$f" -nt /tmp/start_ref ]; then
            FILES_CREATED=$((FILES_CREATED + 1))
            
            # Check content for patch markers (diff, Index, +++, ---)
            if grep -qE "diff --git|Index: |\+\+\+ |--- " "$f"; then
                VALID_CONTENT_FILES=$((VALID_CONTENT_FILES + 1))
            fi
        fi
    done
fi

# 2. CHECK MAILDIR STATE (Folder creation & movement)
MAILDIR="/home/ga/Maildir"
FOLDER_NAME="Pending-Patches"
FOLDER_PATH="$MAILDIR/.$FOLDER_NAME"

FOLDER_EXISTS="false"
EMAILS_IN_FOLDER=0
PATCH_EMAILS_IN_FOLDER=0

if [ -d "$FOLDER_PATH" ]; then
    FOLDER_EXISTS="true"
    # Count emails
    EMAILS_IN_FOLDER=$(find "$FOLDER_PATH/cur" "$FOLDER_PATH/new" -type f | wc -l)
    
    # Check if they are actually patch emails
    if [ "$EMAILS_IN_FOLDER" -gt 0 ]; then
        PATCH_EMAILS_IN_FOLDER=$(grep -lE "\[PATCH\]|diff --git|Index: " "$FOLDER_PATH/cur"/* "$FOLDER_PATH/new"/* 2>/dev/null | wc -l)
    fi
fi

# 3. CHECK DRAFT REPORT
DRAFT_EXISTS="false"
RECIPIENT="release-lead@company.com"

# Search in Drafts and Sent (in case they sent it)
# We look for files containing the recipient address created/modified after start
DRAFT_COUNT=$(grep -l "$RECIPIENT" "$MAILDIR/.Drafts/cur"/* "$MAILDIR/.Drafts/new"/* "$MAILDIR/.Sent/cur"/* "$MAILDIR/.Sent/new"/* 2>/dev/null | wc -l)

if [ "$DRAFT_COUNT" -gt 0 ]; then
    DRAFT_EXISTS="true"
fi

# 4. JSON EXPORT
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "files_created_count": $FILES_CREATED,
    "valid_patch_files_count": $VALID_CONTENT_FILES,
    "folder_exists": $FOLDER_EXISTS,
    "emails_in_folder": $EMAILS_IN_FOLDER,
    "patch_relevance_count": $PATCH_EMAILS_IN_FOLDER,
    "report_draft_exists": $DRAFT_EXISTS,
    "bluemail_running": $(is_bluemail_running && echo "true" || echo "false"),
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Save result
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="