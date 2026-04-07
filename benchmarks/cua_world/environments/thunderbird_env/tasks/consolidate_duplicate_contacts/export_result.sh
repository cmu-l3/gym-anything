#!/bin/bash
echo "=== Exporting Consolidate Duplicate Contacts result ==="

# Take final screenshot before altering UI state
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || DISPLAY=:1 import -window root /tmp/task_final.png 2>/dev/null || true

# Close Thunderbird gracefully so it flushes SQLite buffers/WAL to disk
DISPLAY=:1 wmctrl -c "Mozilla Thunderbird" 2>/dev/null || true
DISPLAY=:1 wmctrl -c "Thunderbird" 2>/dev/null || true
DISPLAY=:1 wmctrl -c "Address Book" 2>/dev/null || true
sleep 3

# Force kill if still lingering
pkill -f thunderbird 2>/dev/null || true
sleep 1

# Find the active Thunderbird profile
PROFILE_DIR=$(find /home/ga/.thunderbird -maxdepth 1 -type d -name "*default*" | head -n 1)

# Copy the address book database to a safe location for the verifier
if [ -f "$PROFILE_DIR/abook.sqlite" ]; then
    cp "$PROFILE_DIR/abook.sqlite" /tmp/abook_export.sqlite
    chmod 666 /tmp/abook_export.sqlite
    echo "Successfully exported abook.sqlite"
else
    echo "ERROR: abook.sqlite not found in $PROFILE_DIR"
fi

# Export a simple JSON manifest
cat << EOF > /tmp/task_result.json
{
    "task_start": $(cat /tmp/task_start_time.txt 2>/dev/null || echo "0"),
    "task_end": $(date +%s),
    "abook_exported": $(if [ -f /tmp/abook_export.sqlite ]; then echo "true"; else echo "false"; fi)
}
EOF
chmod 666 /tmp/task_result.json

echo "=== Export complete ==="