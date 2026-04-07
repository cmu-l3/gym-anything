#!/usr/bin/env bash
set -euo pipefail

echo "=== Exporting Arrangement Conference Workspace Result ==="

export DISPLAY=${DISPLAY:-:1}

# 1. Take Final Screenshot
scrot /tmp/task_final.png 2>/dev/null || true

# 2. Gracefully close Chrome to flush WAL (Write-Ahead Logs) for SQLite & JSON
echo "Gracefully terminating Chrome to flush Preferences, Bookmarks, and SQLite DBs..."
pkill -15 -f "chrome" 2>/dev/null || true
sleep 4

# Force kill any remaining zombie processes
pkill -9 -f "chrome" 2>/dev/null || true

# 3. Copy DBs to stable temp location to prevent locks during verification
CHROME_PROFILE="/home/ga/.config/google-chrome/Default"

if [ -f "$CHROME_PROFILE/History" ]; then
    cp "$CHROME_PROFILE/History" /tmp/History_export.db
    chmod 644 /tmp/History_export.db
fi

if [ -f "$CHROME_PROFILE/Web Data" ]; then
    cp "$CHROME_PROFILE/Web Data" /tmp/WebData_export.db
    chmod 644 /tmp/WebData_export.db
fi

echo "=== Export Complete ==="