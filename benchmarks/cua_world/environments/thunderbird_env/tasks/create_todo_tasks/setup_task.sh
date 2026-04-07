#!/bin/bash
set -e
echo "=== Setting up create_todo_tasks task ==="

source /workspace/scripts/task_utils.sh

# Record task start time for anti-gaming verification
date +%s > /tmp/task_start_time.txt
echo "Task start time: $(cat /tmp/task_start_time.txt)"

PROFILE_DIR="/home/ga/.thunderbird/default-release"
CALENDAR_DIR="${PROFILE_DIR}/calendar-data"

# Ensure calendar-data directory exists
mkdir -p "$CALENDAR_DIR"
chown -R ga:ga "$CALENDAR_DIR"

# Ensure Thunderbird is closed to avoid database locks while clearing
close_thunderbird
sleep 2

# If a local.sqlite exists, remove any pre-existing todos to start clean
if [ -f "${CALENDAR_DIR}/local.sqlite" ]; then
    echo "Cleaning existing todos from calendar database..."
    sqlite3 "${CALENDAR_DIR}/local.sqlite" "DELETE FROM cal_todos;" 2>/dev/null || true
    echo "Existing todos cleared."
fi

# Record initial todo count (should be 0)
INITIAL_TODO_COUNT=0
if [ -f "${CALENDAR_DIR}/local.sqlite" ]; then
    INITIAL_TODO_COUNT=$(sqlite3 "${CALENDAR_DIR}/local.sqlite" "SELECT COUNT(*) FROM cal_todos;" 2>/dev/null || echo "0")
fi
echo "$INITIAL_TODO_COUNT" > /tmp/initial_todo_count.txt
echo "Initial todo count: $INITIAL_TODO_COUNT"

# Start Thunderbird
echo "Starting Thunderbird..."
start_thunderbird
sleep 5

# Wait for Thunderbird window
if ! wait_for_thunderbird_window 30; then
    echo "WARNING: Thunderbird window not detected, attempting restart..."
    start_thunderbird
    sleep 8
    wait_for_thunderbird_window 20 || echo "ERROR: Thunderbird window still not found"
fi

# Maximize Thunderbird and focus it
maximize_thunderbird
sleep 2

# Dismiss any startup dialogs
su - ga -c "DISPLAY=:1 xdotool key Escape" 2>/dev/null || true
sleep 1
su - ga -c "DISPLAY=:1 xdotool key Escape" 2>/dev/null || true
sleep 1

# Take initial screenshot for evidence
take_screenshot /tmp/task_initial.png
echo "Initial screenshot saved to /tmp/task_initial.png"

echo "=== Task setup complete ==="