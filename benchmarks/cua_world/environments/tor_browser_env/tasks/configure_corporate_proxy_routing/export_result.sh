#!/bin/bash
# export_result.sh for configure_corporate_proxy_routing
# Extracts configuration status and prepares it for verifier.py

echo "=== Exporting configure_corporate_proxy_routing task results ==="

TASK_NAME="configure_corporate_proxy_routing"

# 1. Capture final state screenshot
DISPLAY=:1 import -window root /tmp/${TASK_NAME}_final.png 2>/dev/null || \
    DISPLAY=:1 scrot /tmp/${TASK_NAME}_final.png 2>/dev/null || true

TASK_START=$(cat /tmp/${TASK_NAME}_start_ts 2>/dev/null || echo "0")
TASK_END=$(date +%s)

# 2. Find the active torrc file
TORRC_FILE=""
for candidate in \
    "/home/ga/.local/share/torbrowser/tbb/x86_64/tor-browser/Browser/TorBrowser/Data/Tor/torrc" \
    "/home/ga/.local/share/torbrowser/tbb/aarch64/tor-browser/Browser/TorBrowser/Data/Tor/torrc" \
    "/home/ga/.local/share/torbrowser/tbb/tor-browser/Browser/TorBrowser/Data/Tor/torrc"
do
    if [ -f "$candidate" ]; then
        TORRC_FILE="$candidate"
        break
    fi
done

# 3. Analyze the active torrc
ACTIVE_TORRC_HAS_PROXY="false"
ACTIVE_TORRC_PROXY_LINE=""

if [ -n "$TORRC_FILE" ] && [ -f "$TORRC_FILE" ]; then
    # Case-insensitive grep for proxy line matching the briefing
    MATCH=$(grep -iE "^HTTPSProxy 10\.200\.5\.99:8080" "$TORRC_FILE" 2>/dev/null || echo "")
    if [ -n "$MATCH" ]; then
        ACTIVE_TORRC_HAS_PROXY="true"
        ACTIVE_TORRC_PROXY_LINE=$(echo "$MATCH" | head -1)
    fi
fi

# 4. Analyze the backup file
BACKUP_PATH="/home/ga/Documents/torrc_backup.txt"
BACKUP_EXISTS="false"
BACKUP_CREATED_DURING_TASK="false"
BACKUP_HAS_PROXY="false"

if [ -f "$BACKUP_PATH" ]; then
    BACKUP_EXISTS="true"
    BACKUP_MTIME=$(stat -c %Y "$BACKUP_PATH" 2>/dev/null || echo "0")
    
    # Anti-gaming: Ensure it was created/modified after the task started
    if [ "$BACKUP_MTIME" -ge "$TASK_START" ]; then
        BACKUP_CREATED_DURING_TASK="true"
    fi
    
    # Check if the backup actually contains the required directive
    BACKUP_MATCH=$(grep -iE "^HTTPSProxy 10\.200\.5\.99:8080" "$BACKUP_PATH" 2>/dev/null || echo "")
    if [ -n "$BACKUP_MATCH" ]; then
        BACKUP_HAS_PROXY="true"
    fi
fi

# 5. Check if Tor Browser is still running
APP_RUNNING="false"
if pgrep -f "tor-browser" > /dev/null || pgrep -f "firefox.*TorBrowser" > /dev/null; then
    APP_RUNNING="true"
fi

# 6. Generate JSON export
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "active_torrc_found": $([ -n "$TORRC_FILE" ] && echo "true" || echo "false"),
    "active_torrc_has_proxy": $ACTIVE_TORRC_HAS_PROXY,
    "active_torrc_proxy_line": "$ACTIVE_TORRC_PROXY_LINE",
    "backup_exists": $BACKUP_EXISTS,
    "backup_created_during_task": $BACKUP_CREATED_DURING_TASK,
    "backup_has_proxy": $BACKUP_HAS_PROXY,
    "app_running": $APP_RUNNING
}
EOF

# Handle permissions securely
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "=== Task export complete ==="
cat /tmp/task_result.json