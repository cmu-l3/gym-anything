#!/bin/bash
# Setup script for Add Employee task
# Records initial state before the task begins
# CRITICAL: This script FAILS if prerequisites are not met

echo "=== Setting up Add Employee task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Run pre-flight check (BLOCKS until environment is ready)
if ! preflight_check; then
    echo "FATAL: Pre-flight check failed. Cannot start task."
    exit 1
fi

# Take initial screenshot
take_screenshot /tmp/task_initial_screenshot.png

# Record initial employee count
INITIAL_COUNT=$(get_user_count)
echo "$INITIAL_COUNT" > /tmp/initial_employee_count
echo "Initial employee count: $INITIAL_COUNT"

# Verify Sarah Johnson doesn't already exist (would cause false positive)
SARAH_EXISTS=$(timetrex_query "SELECT COUNT(*) FROM users WHERE LOWER(first_name)='sarah' AND LOWER(last_name)='johnson'" 2>/dev/null)
if [ "$SARAH_EXISTS" != "0" ] && [ -n "$SARAH_EXISTS" ]; then
    echo "WARNING: Employee 'Sarah Johnson' already exists in database!"
    echo "This may affect verification. Deleting existing record..."
    timetrex_query "DELETE FROM users WHERE LOWER(first_name)='sarah' AND LOWER(last_name)='johnson'" 2>/dev/null || true
    INITIAL_COUNT=$(get_user_count)
    echo "$INITIAL_COUNT" > /tmp/initial_employee_count
    echo "Updated initial employee count: $INITIAL_COUNT"
fi

# Final verification - ensure we can see the login page
if ! verify_timetrex_accessible; then
    echo "FATAL: TimeTrex login page not accessible at task start!"
    exit 1
fi

echo ""
echo "=== Task Setup Complete - All Prerequisites Met ==="
echo "Task: Add a new employee with the following EXACT details:"
echo "  - First Name: Sarah"
echo "  - Last Name: Johnson"
echo "  - Employee Number: EMP-2024-001"
echo ""
echo "Navigate to the Employee menu, click 'Add Employee', fill in the required fields, and save."
echo "Login credentials: demoadmin1 / demo"
echo ""
