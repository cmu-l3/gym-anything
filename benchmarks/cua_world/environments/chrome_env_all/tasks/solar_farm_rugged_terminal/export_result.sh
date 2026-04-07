#!/usr/bin/env bash
set -euo pipefail

echo "=== Exporting Task Results ==="

# Record task end time
date +%s > /tmp/task_end_time.txt

# Take final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# CRITICAL: Gracefully close Chrome to flush all preferences, Local State, and SQLite databases to disk
echo "Closing Chrome to flush SQLite Web Data and JSON configuration files..."
pkill -f "google-chrome" 2>/dev/null || true
sleep 3

# Force kill if still running
pkill -9 -f "google-chrome" 2>/dev/null || true
sleep 1

echo "=== Export Complete ==="