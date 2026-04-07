#!/bin/bash
# Setup script for Implement Tip of the Day Block task

echo "=== Setting up Tip of the Day Task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start timestamp for anti-gaming
date +%s > /tmp/task_start_timestamp

# Verify BIO101 course exists
COURSE_ID=$(moodle_query "SELECT id FROM mdl_course WHERE shortname='BIO101'" | tr -d '[:space:]')
if [ -z "$COURSE_ID" ]; then
    echo "ERROR: BIO101 course not found! Cannot proceed."
    exit 1
fi
echo "Target Course ID: $COURSE_ID" > /tmp/target_course_id

# Record initial counts to detect changes
INITIAL_GLOSSARY_COUNT=$(moodle_query "SELECT COUNT(*) FROM mdl_glossary WHERE course=$COURSE_ID" | tr -d '[:space:]')
echo "$INITIAL_GLOSSARY_COUNT" > /tmp/initial_glossary_count

# Record initial block count for this course context
# Context level 50 = COURSE
COURSE_CONTEXT_ID=$(moodle_query "SELECT id FROM mdl_context WHERE contextlevel=50 AND instanceid=$COURSE_ID" | tr -d '[:space:]')
if [ -n "$COURSE_CONTEXT_ID" ]; then
    INITIAL_BLOCK_COUNT=$(moodle_query "SELECT COUNT(*) FROM mdl_block_instances WHERE parentcontextid=$COURSE_CONTEXT_ID AND blockname='glossary_random'" | tr -d '[:space:]')
    echo "$COURSE_CONTEXT_ID" > /tmp/course_context_id
else
    INITIAL_BLOCK_COUNT="0"
fi
echo "$INITIAL_BLOCK_COUNT" > /tmp/initial_block_count

# Ensure Firefox is running
echo "Ensuring Firefox is running..."
MOODLE_URL="http://localhost/"

if ! pgrep -f firefox > /dev/null; then
    echo "Starting Firefox..."
    su - ga -c "DISPLAY=:1 firefox '$MOODLE_URL' > /tmp/firefox_task.log 2>&1 &"
    sleep 5
fi

# Wait for and focus Firefox
if ! wait_for_window "firefox\|mozilla\|Moodle" 30; then
    echo "WARNING: Firefox window not detected"
fi

WID=$(get_firefox_window_id)
if [ -n "$WID" ]; then
    focus_window "$WID"
    DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
    sleep 1
fi

# Take initial screenshot
take_screenshot /tmp/task_start_screenshot.png

echo "=== Setup Complete ==="
echo "Initial Glossary Count: $INITIAL_GLOSSARY_COUNT"
echo "Initial Block Count: $INITIAL_BLOCK_COUNT"