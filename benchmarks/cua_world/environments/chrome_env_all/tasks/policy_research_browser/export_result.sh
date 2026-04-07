#!/usr/bin/env bash
set -euo pipefail

echo "=== Exporting Comparative Policy Research Task Result ==="

# Record export start time
date +%s > /tmp/task_end_time.txt

# Take final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || DISPLAY=:1 import -window root /tmp/task_final.png 2>/dev/null || true

# Gracefully close Chrome to force it to flush all JSON and SQLite files to disk
echo "Closing Chrome to flush data..."
pkill -f "google-chrome" 2>/dev/null || true
sleep 3

# Force kill if any zombies remain
pkill -9 -f "google-chrome" 2>/dev/null || true
sleep 1

# Generate a fast summary JSON to help the verifier (optional, verifier pulls direct files too)
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start_time": $(cat /tmp/task_start_time.txt 2>/dev/null || echo 0),
    "task_end_time": $(cat /tmp/task_end_time.txt 2>/dev/null || echo 0),
    "export_complete": true
}
EOF

# Move to standard readable location
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "=== Export Complete ==="