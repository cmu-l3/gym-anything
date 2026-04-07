#!/usr/bin/env bash
set -euo pipefail

echo "=== Exporting Audio Post-Production Setup Result ==="

# Record task end time
date +%s > /tmp/task_end_time.txt

# Capture final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# Gracefully close Chrome to flush JSONs and SQLite WAL files to disk
echo "Closing Chrome to flush data..."
pkill -f "google-chrome" 2>/dev/null || true
sleep 3

# Force kill if still lingering
pkill -9 -f "google-chrome" 2>/dev/null || true
sleep 1

echo "=== Export Complete ==="