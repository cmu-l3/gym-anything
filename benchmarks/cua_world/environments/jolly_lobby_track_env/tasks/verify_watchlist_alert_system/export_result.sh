#!/bin/bash
echo "=== Exporting Verify Watchlist Alert System results ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# 1. Check for Proof Screenshot
PROOF_PATH="/home/ga/Documents/watchlist_alert_proof.png"
PROOF_EXISTS="false"
PROOF_CREATED_DURING_TASK="false"

if [ -f "$PROOF_PATH" ]; then
    PROOF_EXISTS="true"
    PROOF_MTIME=$(stat -c %Y "$PROOF_PATH" 2>/dev/null || echo "0")
    if [ "$PROOF_MTIME" -gt "$TASK_START" ]; then
        PROOF_CREATED_DURING_TASK="true"
    fi
fi

# 2. Check Database for "Audit RedTeam" presence
# We look for the database file in standard locations
DB_FILE=$(find /home/ga/.wine/drive_c -name "*.mdb" -o -name "*.sdf" 2>/dev/null | head -1)
NAME_IN_DB="false"

if [ -f "$DB_FILE" ]; then
    echo "Checking database file: $DB_FILE"
    # Use strings to check for the name since we don't have mdb-tools/sqlcmd guaranteed
    if strings "$DB_FILE" | grep -i "Audit RedTeam" > /dev/null; then
        NAME_IN_DB="true"
    fi
    # Copy DB for verifier analysis if needed (optional, strings check is usually enough here)
    # cp "$DB_FILE" /tmp/lobbytrack_db_dump.mdb
else
    echo "WARNING: Could not locate Lobby Track database file."
fi

# 3. Capture Final State (to check if user cancelled or is still stuck)
take_screenshot /tmp/task_final.png

# 4. Create JSON Result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "proof_screenshot_exists": $PROOF_EXISTS,
    "proof_created_during_task": $PROOF_CREATED_DURING_TASK,
    "name_found_in_db": $NAME_IN_DB,
    "proof_path": "$PROOF_PATH",
    "final_screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to final location
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="