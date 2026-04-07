#!/bin/bash
set -euo pipefail

echo "=== Exporting construction_project_workspace result ==="

# Record export start time
date +%s > /tmp/task_end_time.txt

# Take final screenshot as evidence
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# Gracefully close Chrome to flush all SQLite DBs and JSON files to disk
echo "Sending close signal to Chrome..."
pkill -15 -f "google-chrome" 2>/dev/null || true
pkill -15 -f "chromium" 2>/dev/null || true
sleep 3

# Force kill if any zombies remain
pkill -9 -f "google-chrome" 2>/dev/null || true
pkill -9 -f "chromium" 2>/dev/null || true
sleep 1

echo "Browser data flushed to disk."
echo "=== Export Complete ==="