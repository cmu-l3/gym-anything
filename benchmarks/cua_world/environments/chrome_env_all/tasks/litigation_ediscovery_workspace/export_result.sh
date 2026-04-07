#!/usr/bin/env bash
set -euo pipefail

echo "=== Exporting Litigation E-Discovery Workspace Result ==="

# Record end state screenshots
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# Close Chrome gracefully to ensure JSON and DBs are fully flushed to disk
echo "Closing Chrome to flush SQLite and JSON data..."
pkill -f "google-chrome" 2>/dev/null || true
sleep 3

# Force kill any remaining processes
pkill -9 -f "google-chrome" 2>/dev/null || true
sleep 1

echo "=== Export Complete ==="