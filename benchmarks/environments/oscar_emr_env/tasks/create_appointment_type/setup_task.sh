#!/bin/bash
# Setup script for Create Appointment Type task
# Ensures the appointment type does not exist before starting

echo "=== Setting up Create Appointment Type Task ==="

source /workspace/scripts/task_utils.sh

# 1. Clean up: Remove the specific appointment type if it already exists
echo "Cleaning up any existing 'Mental Health Intake' appointment type..."
oscar_query "DELETE FROM appointment_type WHERE type='Mental Health Intake'" 2>/dev/null || true

# 2. Record task start time (for anti-gaming)
date +%s > /tmp/task_start_time.txt

# 3. Record initial count of appointment types (optional, for debugging)
INITIAL_COUNT=$(oscar_query "SELECT COUNT(*) FROM appointment_type" 2>/dev/null || echo "0")
echo "$INITIAL_COUNT" > /tmp/initial_count.txt
echo "Initial appointment type count: $INITIAL_COUNT"

# 4. Ensure Firefox is running and at login page
ensure_firefox_on_oscar

# 5. Take initial screenshot
take_screenshot /tmp/task_initial_state.png

echo "=== Setup complete ==="
echo "Task: Create 'Mental Health Intake' appointment type (45 mins, Red)"