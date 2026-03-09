#!/bin/bash
# Setup script for CHEM101 Calendar Events task

echo "=== Setting up CHEM101 Calendar Events Task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# =============================================================================
# PRE-TASK HEALTH CHECK
# =============================================================================
echo "Running pre-task Canvas health check..."
if ! ensure_canvas_ready_for_task 5; then
    echo "CRITICAL ERROR: Canvas is not accessible."
    exit 1
fi

# =============================================================================
# DATA PREPARATION
# =============================================================================

# Ensure CHEM101 course exists
echo "Checking for CHEM101 course..."
COURSE_ID=$(canvas_query "SELECT id FROM courses WHERE LOWER(TRIM(course_code))='chem101' AND workflow_state='available' LIMIT 1" 2>/dev/null)

# If not found, create it (fallback mechanism if seed data missing)
if [ -z "$COURSE_ID" ]; then
    echo "CHEM101 not found, creating it..."
    canvas_query "INSERT INTO courses (name, course_code, workflow_state, created_at, updated_at, root_account_id) VALUES ('Chemistry 101', 'CHEM101', 'available', NOW(), NOW(), 1);"
    COURSE_ID=$(canvas_query "SELECT id FROM courses WHERE LOWER(TRIM(course_code))='chem101' AND workflow_state='available' LIMIT 1")
fi

echo "CHEM101 Course ID: $COURSE_ID"
echo "$COURSE_ID" > /tmp/chem101_course_id

# Record initial calendar event count for this course
INITIAL_COUNT="0"
if [ -n "$COURSE_ID" ]; then
    INITIAL_COUNT=$(canvas_query "SELECT COUNT(*) FROM calendar_events WHERE context_id = $COURSE_ID AND context_type = 'Course' AND workflow_state = 'active'" 2>/dev/null || echo "0")
fi
echo "$INITIAL_COUNT" > /tmp/initial_event_count
echo "Initial event count: $INITIAL_COUNT"

# Record start timestamp for anti-gaming
date +%s > /tmp/task_start_time

# =============================================================================
# BROWSER SETUP
# =============================================================================

# Ensure Firefox is running and at login page
if ! pgrep -f "firefox" > /dev/null; then
    echo "Starting Firefox..."
    su - ga -c "DISPLAY=:1 firefox 'http://localhost:3000/login/canvas' &"
    sleep 5
else
    # Navigate to login if already open
    su - ga -c "DISPLAY=:1 firefox -new-window 'http://localhost:3000/login/canvas'"
    sleep 2
fi

# Maximize window
DISPLAY=:1 wmctrl -r "Firefox" -b add,maximized_vert,maximized_horz 2>/dev/null || true

# Take initial screenshot
take_screenshot /tmp/task_start_screenshot.png

echo "=== Setup Complete ==="