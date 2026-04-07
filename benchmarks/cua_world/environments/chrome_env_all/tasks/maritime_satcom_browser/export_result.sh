#!/usr/bin/env bash
set -euo pipefail

echo "=== Exporting Maritime Satcom Browser Optimization Result ==="

# 1. Take final screenshot before altering state
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# 2. Gracefully close Chrome to force it to flush settings to disk
echo "Closing Chrome to flush Preferences and Local State..."
pkill -f "google-chrome" 2>/dev/null || true
sleep 3
pkill -9 -f "google-chrome" 2>/dev/null || true
sleep 1

# 3. Ensure permissions are readable
chmod -R 755 /home/ga/.config/google-chrome/ 2>/dev/null || true

# 4. Copy Web Data (SQLite) out so it doesn't get locked
cp /home/ga/.config/google-chrome/Default/Web\ Data /tmp/WebData_export 2>/dev/null || true
chmod 666 /tmp/WebData_export 2>/dev/null || true

date +%s > /tmp/task_end_time.txt

echo "=== Export Complete ==="