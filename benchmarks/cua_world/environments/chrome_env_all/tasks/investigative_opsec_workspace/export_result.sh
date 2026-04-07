#!/bin/bash
echo "=== Exporting OPSEC Workspace Result ==="

# Record task end time
date +%s > /tmp/task_end_time.txt

# Take final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# Close Chrome gracefully so it flushes all in-memory Bookmarks/Preferences to disk
echo "Flushing Chrome data to disk..."
pkill -f "google-chrome" 2>/dev/null || true
sleep 3
pkill -9 -f "google-chrome" 2>/dev/null || true
sleep 1

# Gather file modification timestamps to prove the agent did work
BM_MTIME=$(stat -c %Y /home/ga/.config/google-chrome/Default/Bookmarks 2>/dev/null || echo "0")
PREFS_MTIME=$(stat -c %Y /home/ga/.config/google-chrome/Default/Preferences 2>/dev/null || echo "0")

# Write metadata to a JSON file for the verifier
cat > /tmp/export_metadata.json << EOF
{
    "bookmarks_mtime": $BM_MTIME,
    "preferences_mtime": $PREFS_MTIME
}
EOF

echo "=== Export complete ==="