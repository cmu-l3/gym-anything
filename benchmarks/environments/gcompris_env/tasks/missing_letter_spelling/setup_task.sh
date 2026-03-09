#!/bin/bash
set -e

echo "=== Setting up Missing Letter Spelling task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# ==============================================================================
# DATABASE STATE RECORDING
# ==============================================================================
# GCompris-qt stores logs in sqlite. We want to know the initial state
# so we can count NEW entries later.
DB_PATH="/home/ga/.local/share/GCompris/gcompris-qt.db"
INITIAL_LOG_COUNT="0"

if [ -f "$DB_PATH" ]; then
    # Check if sqlite3 is available, otherwise just rely on file mtime or existence
    if command -v sqlite3 &> /dev/null; then
        INITIAL_LOG_COUNT=$(sqlite3 "$DB_PATH" "SELECT COUNT(*) FROM logs;" 2>/dev/null || echo "0")
    fi
fi
echo "$INITIAL_LOG_COUNT" > /tmp/initial_db_count.txt
echo "Initial DB Log Count: $INITIAL_LOG_COUNT"

# ==============================================================================
# APPLICATION SETUP
# ==============================================================================

# Ensure clean slate
kill_gcompris

# Launch GCompris at Main Menu
# We do NOT navigate to the specific category; the agent must find it.
echo "Launching GCompris..."
launch_gcompris

# Maximize for visibility
maximize_gcompris

# Wait a moment for the menu to settle
sleep 2

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="