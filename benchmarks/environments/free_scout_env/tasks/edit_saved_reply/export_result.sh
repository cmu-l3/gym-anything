#!/bin/bash
set -e
echo "=== Exporting edit_saved_reply results ==="

source /workspace/scripts/task_utils.sh

# Record end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TARGET_ID=$(cat /tmp/target_saved_reply_id.txt 2>/dev/null || echo "0")
INITIAL_COUNT=$(cat /tmp/initial_count.txt 2>/dev/null || echo "0")

# Take final screenshot
take_screenshot /tmp/task_final.png

# === Gather Data ===

# 1. Get current saved replies count for this mailbox
MAILBOX_ID=$(ensure_mailbox_exists "IT Support" "itsupport@helpdesk.local")
CURRENT_COUNT=$(fs_query "SELECT COUNT(*) FROM saved_replies WHERE mailbox_id = $MAILBOX_ID" 2>/dev/null || echo "0")

# 2. Get the specific target saved reply (by ID) to see if it was edited
# We use a special query to get fields as a JSON object if possible, or simple select
# Note: JSON_OBJECT might not be available in all MariaDB versions, so we'll use python to format
TARGET_DATA_RAW=$(fs_query "SELECT name, text, updated_at FROM saved_replies WHERE id = $TARGET_ID" 2>/dev/null)

TARGET_STILL_EXISTS="false"
TARGET_NAME=""
TARGET_BODY=""
TARGET_UPDATED_AT=""

if [ -n "$TARGET_DATA_RAW" ]; then
    TARGET_STILL_EXISTS="true"
    TARGET_NAME=$(echo "$TARGET_DATA_RAW" | cut -f1)
    TARGET_BODY=$(echo "$TARGET_DATA_RAW" | cut -f2)
    TARGET_UPDATED_AT=$(echo "$TARGET_DATA_RAW" | cut -f3)
fi

# 3. Check for ANY saved reply that matches our success criteria (in case they created a new one)
# Look for name "SSO Password Reset Guide"
SUCCESS_CANDIDATE_RAW=$(fs_query "SELECT id, name, text, updated_at FROM saved_replies WHERE name LIKE '%SSO Password Reset Guide%' AND mailbox_id = $MAILBOX_ID ORDER BY updated_at DESC LIMIT 1" 2>/dev/null)

CANDIDATE_FOUND="false"
CANDIDATE_ID=""
CANDIDATE_NAME=""
CANDIDATE_BODY=""
CANDIDATE_UPDATED_AT=""

if [ -n "$SUCCESS_CANDIDATE_RAW" ]; then
    CANDIDATE_FOUND="true"
    CANDIDATE_ID=$(echo "$SUCCESS_CANDIDATE_RAW" | cut -f1)
    CANDIDATE_NAME=$(echo "$SUCCESS_CANDIDATE_RAW" | cut -f2)
    CANDIDATE_BODY=$(echo "$SUCCESS_CANDIDATE_RAW" | cut -f3)
    CANDIDATE_UPDATED_AT=$(echo "$SUCCESS_CANDIDATE_RAW" | cut -f4)
fi

# 4. Check if the "Old" one still exists (by name)
OLD_NAME_EXISTS=$(fs_query "SELECT COUNT(*) FROM saved_replies WHERE name = 'Password Reset Instructions' AND mailbox_id = $MAILBOX_ID" 2>/dev/null || echo "0")

# === Create JSON Output ===
# Python script to safely escape and format JSON
python3 << EOF
import json
import time
import sys

def safe_str(s):
    return s if s else ""

result = {
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "initial_count": int("$INITIAL_COUNT"),
    "current_count": int("$CURRENT_COUNT"),
    "target_id": int("$TARGET_ID"),
    
    "target_still_exists": "$TARGET_STILL_EXISTS" == "true",
    "target_name": safe_str("""$TARGET_NAME"""),
    "target_body": safe_str("""$TARGET_BODY"""),
    "target_updated_at": safe_str("""$TARGET_UPDATED_AT"""),
    
    "candidate_found": "$CANDIDATE_FOUND" == "true",
    "candidate_id": safe_str("""$CANDIDATE_ID"""),
    "candidate_name": safe_str("""$CANDIDATE_NAME"""),
    "candidate_body": safe_str("""$CANDIDATE_BODY"""),
    
    "old_name_exists": int("$OLD_NAME_EXISTS") > 0,
    "timestamp": time.time()
}

with open('/tmp/task_result.json', 'w') as f:
    json.dump(result, f, indent=2)
EOF

# Move to standard location with permissions
chmod 666 /tmp/task_result.json 2>/dev/null || true

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="