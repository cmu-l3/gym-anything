#!/bin/bash
echo "=== Setting up Write Prescription Task ==="

source /workspace/scripts/task_utils.sh

# Ensure LibreHealth EHR is running
wait_for_librehealth 60

# Record initial prescription count (anti-gaming)
INITIAL_COUNT=$(librehealth_query "SELECT COUNT(*) FROM prescriptions" 2>/dev/null || echo "0")
echo "$INITIAL_COUNT" > /tmp/lh_initial_rx_count
echo "Initial prescription count: $INITIAL_COUNT"

TASK_START=$(date +%s)
echo "$TASK_START" > /tmp/lh_task_start
echo "Task start timestamp: $TASK_START"

# Get a sample patient from NHANES
SAMPLE_PID=$(librehealth_query "SELECT pid FROM patient_data LIMIT 1" 2>/dev/null)
SAMPLE_NAME=$(librehealth_query "SELECT CONCAT(fname,' ',lname) FROM patient_data LIMIT 1" 2>/dev/null)
echo "Sample NHANES patient: ${SAMPLE_NAME} (pid=${SAMPLE_PID})"

# Open Firefox at patient selection page
restart_firefox "http://localhost:8000/interface/patient_file/patient_select.php"

take_screenshot /tmp/task_start_screenshot.png

echo ""
echo "=== Write Prescription Task Ready ==="
echo ""
echo "TASK: Write a prescription for an existing NHANES patient:"
echo "  Drug:       Metformin"
echo "  Dosage:     500mg"
echo "  Directions: Take one tablet by mouth twice daily with meals"
echo "  Quantity:   60"
echo "  Refills:    3"
echo ""
echo "Login: admin / password"
echo "Sample patient: ${SAMPLE_NAME}"
