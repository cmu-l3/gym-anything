#!/bin/bash
# Setup script for Resolve Medical Problem task

echo "=== Setting up Resolve Medical Problem Task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Target patient
PATIENT_PID=1
PATIENT_NAME="Philip Sipes"

# Record task start time (for anti-gaming timestamp checks)
date +%s > /tmp/task_start_time.txt
echo "Task start timestamp: $(cat /tmp/task_start_time.txt)"

# Verify patient exists
echo "Verifying patient $PATIENT_NAME (pid=$PATIENT_PID) exists..."
PATIENT_CHECK=$(openemr_query "SELECT pid, fname, lname FROM patient_data WHERE pid=$PATIENT_PID" 2>/dev/null)
if [ -z "$PATIENT_CHECK" ]; then
    echo "ERROR: Patient not found in database!"
    exit 1
fi
echo "Patient found: $PATIENT_CHECK"

# Check if bronchitis problem exists, if not create it
echo "Checking for Acute bronchitis problem..."
PROBLEM_EXISTS=$(openemr_query "SELECT COUNT(*) FROM lists WHERE pid=$PATIENT_PID AND type='medical_problem' AND (title LIKE '%ronchitis%' OR title LIKE '%RONCHITIS%')" 2>/dev/null || echo "0")

if [ "$PROBLEM_EXISTS" -eq "0" ] || [ -z "$PROBLEM_EXISTS" ]; then
    echo "Creating Acute bronchitis problem for patient..."
    # Calculate date 21 days ago for begin date
    BEGIN_DATE=$(date -d "-21 days" +%Y-%m-%d)
    openemr_query "INSERT INTO lists (pid, type, title, begdate, diagnosis, outcome, date, activity) VALUES ($PATIENT_PID, 'medical_problem', 'Acute bronchitis', '$BEGIN_DATE', 'ICD10:J20.9', 1, NOW(), 1)" 2>/dev/null
    echo "Created bronchitis problem with begin date: $BEGIN_DATE"
else
    echo "Bronchitis problem already exists"
fi

# CRITICAL: Ensure the bronchitis problem has NULL enddate (reset if previously resolved)
echo "Ensuring bronchitis problem is currently ACTIVE (enddate = NULL)..."
openemr_query "UPDATE lists SET enddate = NULL WHERE pid = $PATIENT_PID AND type = 'medical_problem' AND (title LIKE '%ronchitis%' OR title LIKE '%RONCHITIS%')" 2>/dev/null

# Get the problem ID and original begin date for verification
PROBLEM_DATA=$(openemr_query "SELECT id, begdate, title FROM lists WHERE pid=$PATIENT_PID AND type='medical_problem' AND (title LIKE '%ronchitis%' OR title LIKE '%RONCHITIS%') ORDER BY id DESC LIMIT 1" 2>/dev/null)

if [ -n "$PROBLEM_DATA" ]; then
    PROBLEM_ID=$(echo "$PROBLEM_DATA" | cut -f1)
    ORIGINAL_BEGDATE=$(echo "$PROBLEM_DATA" | cut -f2)
    PROBLEM_TITLE=$(echo "$PROBLEM_DATA" | cut -f3)
    
    echo "$PROBLEM_ID" > /tmp/target_problem_id.txt
    echo "$ORIGINAL_BEGDATE" > /tmp/original_begdate.txt
    echo "$PROBLEM_TITLE" > /tmp/original_title.txt
    
    echo "Target problem ID: $PROBLEM_ID"
    echo "Original begin date: $ORIGINAL_BEGDATE"
    echo "Problem title: $PROBLEM_TITLE"
else
    echo "WARNING: Could not retrieve problem data"
fi

# Record initial problem count (to detect if agent creates new instead of editing)
INITIAL_BRONCHITIS_COUNT=$(openemr_query "SELECT COUNT(*) FROM lists WHERE pid=$PATIENT_PID AND type='medical_problem' AND (title LIKE '%ronchitis%' OR title LIKE '%RONCHITIS%')" 2>/dev/null || echo "0")
echo "$INITIAL_BRONCHITIS_COUNT" > /tmp/initial_bronchitis_count.txt
echo "Initial bronchitis problem count: $INITIAL_BRONCHITIS_COUNT"

# Verify the problem is currently active (enddate is NULL)
CURRENT_ENDDATE=$(openemr_query "SELECT enddate FROM lists WHERE id=$PROBLEM_ID" 2>/dev/null)
echo "Current enddate (should be empty/NULL): '$CURRENT_ENDDATE'"

# Ensure Firefox is running with OpenEMR
echo "Ensuring Firefox is running..."
OPENEMR_URL="http://localhost/interface/login/login.php?site=default"

if ! pgrep -f firefox > /dev/null; then
    echo "Starting Firefox..."
    su - ga -c "DISPLAY=:1 firefox '$OPENEMR_URL' > /tmp/firefox_task.log 2>&1 &"
    sleep 5
fi

# Wait for Firefox window
if ! wait_for_window "firefox\|mozilla\|OpenEMR" 30; then
    echo "WARNING: Firefox window not detected"
fi

# Focus and maximize Firefox window
echo "Focusing Firefox window..."
WID=$(get_firefox_window_id)
if [ -n "$WID" ]; then
    focus_window "$WID"
    DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
    sleep 1
fi

# Take initial screenshot
sleep 2
take_screenshot /tmp/task_initial.png

echo ""
echo "=== Resolve Medical Problem Task Setup Complete ==="
echo ""
echo "TASK: Mark Medical Problem as Resolved"
echo "======================================="
echo ""
echo "Patient: $PATIENT_NAME (PID: $PATIENT_PID)"
echo "Problem: Acute bronchitis (currently ACTIVE - no end date)"
echo ""
echo "Instructions:"
echo "  1. Log in to OpenEMR (admin / pass)"
echo "  2. Find patient Philip Sipes"
echo "  3. Navigate to Medical Problems / Issues"
echo "  4. Edit the 'Acute bronchitis' entry"
echo "  5. Set the End Date to today's date"
echo "  6. Save the changes"
echo ""
echo "The problem should be EDITED, not recreated."
echo ""