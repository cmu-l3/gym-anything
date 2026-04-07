#!/usr/bin/env bash
set -euo pipefail

echo "=== Exporting Aviation Maintenance Terminal result ==="

# Take final screenshot showing end state
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# Gracefully close Chrome to flush all SQLite DBs and JSON Preferences to disk
echo "Closing Chrome to flush data..."
pkill -f "google-chrome" 2>/dev/null || true
sleep 3

# Force kill if hung
pkill -9 -f "google-chrome" 2>/dev/null || true
sleep 1

echo "=== Export complete ==="