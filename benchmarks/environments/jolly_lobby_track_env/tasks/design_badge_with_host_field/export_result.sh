#!/bin/bash
set -e
echo "=== Exporting Badge Design Result ==="

source /workspace/scripts/task_utils.sh

TASK_START=$(cat /tmp/design_badge_with_host_field_start_time 2>/dev/null || echo "0")
TASK_END=$(date +%s)

PROOF_PATH="/home/ga/Desktop/badge_host_proof.png"
DB_FILE=""
TEMPLATE_FILE=""

# 1. Check Proof Screenshot
PROOF_EXISTS="false"
PROOF_CREATED_DURING_TASK="false"
if [ -f "$PROOF_PATH" ]; then
    PROOF_EXISTS="true"
    PROOF_MTIME=$(stat -c %Y "$PROOF_PATH")
    if [ "$PROOF_MTIME" -gt "$TASK_START" ]; then
        PROOF_CREATED_DURING_TASK="true"
    fi
fi

# 2. Check Database for Visitor Record "Alice Verifier"
# Since we don't have mdbtools guaranteed, we'll use grep on the binary file
# This is a heuristic but effective for checking if the text was written to the DB
DB_FOUND="false"
VISITOR_IN_DB="false"
HOST_IN_DB="false"

# Locate the main database file (recursive search in Wine prefix)
# Typical path: C:\ProgramData\Jolly Technologies\Lobby Track\Free\Data\LobbyTrack.mdb
# Or in Documents
POSSIBLE_DBS=$(find /home/ga/.wine/drive_c -name "*.mdb" -o -name "*.sdf" 2>/dev/null)

for db in $POSSIBLE_DBS; do
    # Skip sample dbs if they are just templates, look for the one modified recently or large
    if grep -a "Alice" "$db" | grep -a "Verifier" > /dev/null; then
        DB_FOUND="true"
        VISITOR_IN_DB="true"
        echo "Found visitor in DB: $db"
    fi
    if grep -a "Bob" "$db" | grep -a "Manager" > /dev/null; then
        HOST_IN_DB="true"
    fi
done

# 3. Check for Modified Badge Templates
# Look for any files modified during the task in common template locations
TEMPLATE_MODIFIED="false"
TEMPLATE_DIR_1="/home/ga/.wine/drive_c/ProgramData/Jolly Technologies"
TEMPLATE_DIR_2="/home/ga/.wine/drive_c/users/Public/Documents/Jolly Technologies"

# Find any file modified after start time in these dirs
MODIFIED_FILES=$(find "$TEMPLATE_DIR_1" "$TEMPLATE_DIR_2" -type f -newermt "@$TASK_START" 2>/dev/null | head -5)
if [ -n "$MODIFIED_FILES" ]; then
    TEMPLATE_MODIFIED="true"
    echo "Modified files detected: $MODIFIED_FILES"
fi

# 4. Final Screenshot
take_screenshot /tmp/task_final.png

# 5. Create Result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "proof_exists": $PROOF_EXISTS,
    "proof_created_during_task": $PROOF_CREATED_DURING_TASK,
    "proof_path": "$PROOF_PATH",
    "visitor_found_in_db": $VISITOR_IN_DB,
    "host_found_in_db": $HOST_IN_DB,
    "template_modified": $TEMPLATE_MODIFIED,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to standard location
mv "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json

echo "=== Export Complete ==="
cat /tmp/task_result.json