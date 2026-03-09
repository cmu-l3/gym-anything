#!/bin/bash
echo "=== Setting up Add Medical Problem Task ==="

source /workspace/scripts/task_utils.sh

# Ensure LibreHealth EHR is running
wait_for_librehealth 60

# Target patient: Allan Thomas (pid=782)
TARGET_PID=782
TARGET_NAME="Allan Thomas"

# Record initial medical problem count (anti-gaming)
INITIAL_COUNT=$(librehealth_query "SELECT COUNT(*) FROM lists WHERE type='medical_problem'" 2>/dev/null || echo "0")
echo "$INITIAL_COUNT" > /tmp/lh_initial_problems_count
echo "Initial medical problems count: $INITIAL_COUNT"

TASK_START=$(date +%s)
echo "$TASK_START" > /tmp/lh_task_start
echo "$TARGET_PID" > /tmp/lh_target_pid
echo "Task start timestamp: $TASK_START"
echo "Target patient: ${TARGET_NAME} (pid=${TARGET_PID})"

# Open Firefox at patient search, filtered to 'Thomas'
restart_firefox "http://localhost:8000/interface/patient_file/patient_select.php"

take_screenshot /tmp/task_start_screenshot.png

echo ""
echo "=== Add Medical Problem Task Ready ==="
echo ""
echo "TASK: Add a medical problem to patient '${TARGET_NAME}' (pid=${TARGET_PID}):"
echo "  - Search for last name 'Thomas' in the patient search box"
echo "  - Click on 'Allan Thomas' to open their chart"
echo "  - Navigate to the Issues section (or Problems/Issues tab)"
echo "  - Click 'Add' to add a new medical problem"
echo "  - Title: Type 2 Diabetes Mellitus"
echo "  - ICD code: E11"
echo "  - Status: Active"
echo "  - Save the problem"
echo ""
echo "Login: admin / password"
