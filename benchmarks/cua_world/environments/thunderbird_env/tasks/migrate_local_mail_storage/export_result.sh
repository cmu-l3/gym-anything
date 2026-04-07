#!/bin/bash
echo "=== Exporting task results ==="

# Take final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || \
    DISPLAY=:1 import -window root /tmp/task_final.png 2>/dev/null || true

# Export prefs.js safely so the verifier can read it
PREFS_FILE="/home/ga/.thunderbird/default-release/prefs.js"
if [ -f "$PREFS_FILE" ]; then
    cp "$PREFS_FILE" /tmp/exported_prefs.js
    chmod 666 /tmp/exported_prefs.js
fi

# Check migrated files in target destination
TARGET_DIR="/home/ga/ArchiveDrive/MailStore"
TARGET_INBOX="$TARGET_DIR/Inbox"
MIGRATED_EXISTS="false"
MIGRATED_COUNT=0

if [ -f "$TARGET_INBOX" ]; then
    MIGRATED_EXISTS="true"
    MIGRATED_COUNT=$(grep -c "^From " "$TARGET_INBOX" 2>/dev/null || echo "0")
    MIGRATED_COUNT=$(echo "$MIGRATED_COUNT" | tr -d '[:space:]')
    if ! [[ "$MIGRATED_COUNT" =~ ^[0-9]+$ ]]; then MIGRATED_COUNT=0; fi
fi

# Check if application is running
TB_RUNNING="false"
if pgrep -f "thunderbird" > /dev/null; then
    TB_RUNNING="true"
fi

INITIAL_COUNT=$(cat /tmp/initial_inbox_count.txt 2>/dev/null || echo "0")
INITIAL_COUNT=$(echo "$INITIAL_COUNT" | tr -d '[:space:]')
if ! [[ "$INITIAL_COUNT" =~ ^[0-9]+$ ]]; then INITIAL_COUNT=0; fi

# Serialize to JSON via tempfile
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "migrated_exists": $MIGRATED_EXISTS,
    "migrated_count": $MIGRATED_COUNT,
    "initial_count": $INITIAL_COUNT,
    "tb_running": $TB_RUNNING
}
EOF

mv "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json

echo "=== Export complete ==="