#!/bin/bash
set -euo pipefail

echo "=== Exporting E-sports Stage Admin Task Result ==="

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# Gracefully close Chrome to flush Preferences, Local State, and Bookmarks to disk
echo "Closing Chrome to flush config files..."
pkill -f "google-chrome" 2>/dev/null || true
sleep 3
pkill -9 -f "google-chrome" 2>/dev/null || true
sleep 1

# Identify which profile dir was actively used (fallback logic)
CHROME_PROFILE="/home/ga/.config/google-chrome/Default"
CHROME_CDP_PROFILE="/home/ga/.config/google-chrome-cdp/Default"
CHROME_LOCAL_STATE="/home/ga/.config/google-chrome/Local State"
CHROME_CDP_LOCAL_STATE="/home/ga/.config/google-chrome-cdp/Local State"

# Write metadata wrapper for verifier
cat > /tmp/task_result.json << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "primary_profile": "$CHROME_PROFILE",
    "cdp_profile": "$CHROME_CDP_PROFILE",
    "local_state": "$CHROME_LOCAL_STATE",
    "cdp_local_state": "$CHROME_CDP_LOCAL_STATE",
    "screenshot_path": "/tmp/task_final.png"
}
EOF

echo "Result metadata saved to /tmp/task_result.json"
echo "=== Export complete ==="