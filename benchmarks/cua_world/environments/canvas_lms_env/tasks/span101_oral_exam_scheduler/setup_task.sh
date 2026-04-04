#!/bin/bash
# Setup script for SPAN101 Oral Exam Scheduler task

echo "=== Setting up SPAN101 Oral Exam Scheduler Task ==="

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

# Get SPAN101 course ID
echo "Finding SPAN101 course..."
COURSE_DATA=$(canvas_query "SELECT id FROM courses WHERE LOWER(TRIM(course_code))='span101' AND workflow_state='available' LIMIT 1" 2>/dev/null || echo "")

# If SPAN101 doesn't exist (it should from seed data, but just in case), create it
if [ -z "$COURSE_DATA" ]; then
    echo "SPAN101 not found, creating it..."
    # We rely on seed data usually, but this is a fallback
    # In a real scenario, we might fail here, but let's try to proceed if possible or fail hard if strict.
    # The environment seed data usually includes BIO101, CS110, HIST201 etc. 
    # If SPAN101 isn't standard, we should create it via rails runner or SQL.
    # For this task, we assume the environment has been seeded with standard courses or we use a standard one.
    # Let's assume SPAN101 exists or we use one of the standard ones and rename it? 
    # Better: Ensure SPAN101 exists via SQL insertion if missing to guarantee task validity.
    
    # Insert SPAN101 if missing
    canvas_query "INSERT INTO courses (name, course_code, workflow_state, created_at, updated_at, root_account_id, enrollment_term_id) VALUES ('Elementary Spanish I', 'SPAN101', 'available', NOW(), NOW(), 1, 1);"
    COURSE_DATA=$(canvas_query "SELECT id FROM courses WHERE LOWER(TRIM(course_code))='span101' LIMIT 1")
fi

if [ -n "$COURSE_DATA" ]; then
    COURSE_ID="$COURSE_DATA"
    echo "SPAN101 course ID: $COURSE_ID"
    echo "$COURSE_ID" > /tmp/span101_course_id
else
    echo "CRITICAL: Could not find or create SPAN101 course"
    exit 1
fi

# Record initial appointment group count for SPAN101
# Appointment groups are linked via appointment_group_contexts
INITIAL_COUNT=$(canvas_query "SELECT COUNT(*) FROM appointment_groups g JOIN appointment_group_contexts c ON g.id = c.appointment_group_id WHERE c.context_id = $COURSE_ID AND c.context_type = 'Course' AND g.workflow_state = 'active'" 2>/dev/null || echo "0")
echo "$INITIAL_COUNT" > /tmp/initial_group_count
echo "Initial appointment groups: $INITIAL_COUNT"

# Record start time
date +%s > /tmp/task_start_time.txt

# Take initial screenshot
take_screenshot /tmp/task_start_screenshot.png

# Save evidence
mkdir -p /workspace/evidence 2>/dev/null || true
cp /tmp/task_start_screenshot.png /workspace/evidence/span101_scheduler_initial.png 2>/dev/null || true

echo "=== Setup Complete ==="