#!/bin/bash
# Setup script for BIO101 Final Exam Configuration task

echo "=== Setting up BIO101 Final Exam Task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# =============================================================================
# PRE-TASK HEALTH CHECK
# =============================================================================
if ! ensure_canvas_ready_for_task 5; then
    echo "CRITICAL ERROR: Canvas is not accessible."
    exit 1
fi

# Get BIO101 course ID
echo "Finding BIO101 course..."
COURSE_ID=$(canvas_query "SELECT id FROM courses WHERE LOWER(TRIM(course_code))='bio101' AND workflow_state='available' LIMIT 1")

if [ -z "$COURSE_ID" ]; then
    echo "CRITICAL: BIO101 course not found. Attempting to seed..."
    # Fallback seeding if course doesn't exist (should exist from global setup)
    /workspace/scripts/setup_canvas.sh > /dev/null 2>&1
    COURSE_ID=$(canvas_query "SELECT id FROM courses WHERE LOWER(TRIM(course_code))='bio101' AND workflow_state='available' LIMIT 1")
fi

if [ -z "$COURSE_ID" ]; then
    echo "ERROR: Could not find or create BIO101 course."
    exit 1
fi

echo "BIO101 Course ID: $COURSE_ID"
echo "$COURSE_ID" > /tmp/bio101_course_id

# Record initial quiz count for BIO101
INITIAL_COUNT=$(canvas_query "SELECT COUNT(*) FROM quizzes WHERE context_id=$COURSE_ID AND context_type='Course' AND workflow_state != 'deleted'")
echo "$INITIAL_COUNT" > /tmp/initial_quiz_count
echo "Initial quiz count: $INITIAL_COUNT"

# Record task start time for timestamp verification
date +%s > /tmp/task_start_time

# Take initial screenshot
take_screenshot /tmp/task_start_screenshot.png

echo "=== Setup Complete ==="