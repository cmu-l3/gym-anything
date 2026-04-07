#!/bin/bash
# export_result.sh - Post-task hook for full_page_osint_capture
set -e

echo "=== Exporting full_page_osint_capture results ==="

TASK_START=$(cat /tmp/task_start_ts 2>/dev/null || echo "0")
TASK_END=$(date +%s)

# Take final state screenshot
DISPLAY=:1 import -window root /tmp/task_end.png 2>/dev/null || \
    DISPLAY=:1 scrot /tmp/task_end.png 2>/dev/null || true

# Target files
HISTORY_PNG="/home/ga/Documents/history_evidence.png"
COMMUNITY_PNG="/home/ga/Documents/community_evidence.png"
COC_TXT="/home/ga/Documents/chain_of_custody.txt"

# Check history_evidence.png
HISTORY_EXISTS="false"
HISTORY_MTIME=0
HISTORY_SIZE=0
if [ -f "$HISTORY_PNG" ]; then
    HISTORY_EXISTS="true"
    HISTORY_MTIME=$(stat -c %Y "$HISTORY_PNG" 2>/dev/null || echo "0")
    HISTORY_SIZE=$(stat -c %s "$HISTORY_PNG" 2>/dev/null || echo "0")
    # Copy to tmp to ensure permission safety for verifier copy_from_env
    cp "$HISTORY_PNG" /tmp/history_evidence.png 2>/dev/null || true
    chmod 666 /tmp/history_evidence.png 2>/dev/null || true
fi

# Check community_evidence.png
COMMUNITY_EXISTS="false"
COMMUNITY_MTIME=0
COMMUNITY_SIZE=0
if [ -f "$COMMUNITY_PNG" ]; then
    COMMUNITY_EXISTS="true"
    COMMUNITY_MTIME=$(stat -c %Y "$COMMUNITY_PNG" 2>/dev/null || echo "0")
    COMMUNITY_SIZE=$(stat -c %s "$COMMUNITY_PNG" 2>/dev/null || echo "0")
    cp "$COMMUNITY_PNG" /tmp/community_evidence.png 2>/dev/null || true
    chmod 666 /tmp/community_evidence.png 2>/dev/null || true
fi

# Check chain_of_custody.txt
COC_EXISTS="false"
COC_MTIME=0
COC_SIZE=0
if [ -f "$COC_TXT" ]; then
    COC_EXISTS="true"
    COC_MTIME=$(stat -c %Y "$COC_TXT" 2>/dev/null || echo "0")
    COC_SIZE=$(stat -c %s "$COC_TXT" 2>/dev/null || echo "0")
    cp "$COC_TXT" /tmp/chain_of_custody.txt 2>/dev/null || true
    chmod 666 /tmp/chain_of_custody.txt 2>/dev/null || true
fi

# Check if browser is running
TOR_RUNNING="false"
if DISPLAY=:1 wmctrl -l 2>/dev/null | grep -iE "tor browser" > /dev/null; then
    TOR_RUNNING="true"
fi

# Write metadata JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "history_exists": $HISTORY_EXISTS,
    "history_mtime": $HISTORY_MTIME,
    "history_size": $HISTORY_SIZE,
    "community_exists": $COMMUNITY_EXISTS,
    "community_mtime": $COMMUNITY_MTIME,
    "community_size": $COMMUNITY_SIZE,
    "coc_exists": $COC_EXISTS,
    "coc_mtime": $COC_MTIME,
    "coc_size": $COC_SIZE,
    "tor_running": $TOR_RUNNING
}
EOF

rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "=== Export complete ==="
cat /tmp/task_result.json