#!/bin/bash
# Setup script for Create Care Plan task

echo "=== Setting up Create Care Plan Task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh || true

# Configuration
PATIENT_PID=5
PATIENT_NAME="Jayme Kunze"

# Record task start time for anti-gaming verification
date +%s > /tmp/task_start_time.txt
echo "Task start time recorded: $(cat /tmp/task_start_time.txt)"

# Verify OpenEMR is running and accessible
echo "Verifying OpenEMR is accessible..."
for i in {1..30}; do
    HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" "http://localhost/interface/login/login.php?site=default" 2>/dev/null)
    if [ "$HTTP_CODE" = "200" ]; then
        echo "OpenEMR is accessible (HTTP $HTTP_CODE)"
        break
    fi
    sleep 2
done

# Verify patient Jayme Kunze exists
echo "Verifying patient $PATIENT_NAME exists..."
PATIENT_CHECK=$(docker exec openemr-mysql mysql -u openemr -popenemr openemr -N -e \
    "SELECT pid, fname, lname FROM patient_data WHERE pid=$PATIENT_PID" 2>/dev/null)
if [ -z "$PATIENT_CHECK" ]; then
    echo "ERROR: Patient $PATIENT_NAME (pid=$PATIENT_PID) not found in database"
    exit 1
fi
echo "Patient verified: $PATIENT_CHECK"

# Verify diabetes diagnosis exists for patient
echo "Verifying diabetes diagnosis..."
DIABETES_CHECK=$(docker exec openemr-mysql mysql -u openemr -popenemr openemr -N -e \
    "SELECT COUNT(*) FROM lists WHERE pid=$PATIENT_PID AND type='medical_problem' AND (title LIKE '%Diabetes%' OR diagnosis LIKE '%44054006%')" 2>/dev/null)
if [ "$DIABETES_CHECK" -lt 1 ]; then
    echo "WARNING: Diabetes diagnosis not found, adding for task setup..."
    docker exec openemr-mysql mysql -u openemr -popenemr openemr -e \
        "INSERT INTO lists (date, type, pid, title, diagnosis, begdate, activity) VALUES (NOW(), 'medical_problem', $PATIENT_PID, 'Type 2 Diabetes Mellitus', 'SNOMED-CT:44054006', '1980-10-11', 1)" 2>/dev/null || true
fi
echo "Diabetes diagnosis verified"

# Record initial care plan related counts for anti-gaming
echo "Recording initial state..."

# Count forms that might be care plans
INITIAL_FORMS=$(docker exec openemr-mysql mysql -u openemr -popenemr openemr -N -e \
    "SELECT COUNT(*) FROM forms WHERE pid=$PATIENT_PID AND (formdir LIKE '%care%' OR form_name LIKE '%care%' OR form_name LIKE '%Care%')" 2>/dev/null || echo "0")
echo "$INITIAL_FORMS" > /tmp/initial_forms_count.txt
echo "Initial forms count: $INITIAL_FORMS"

# Count care plan related list entries
INITIAL_LISTS=$(docker exec openemr-mysql mysql -u openemr -popenemr openemr -N -e \
    "SELECT COUNT(*) FROM lists WHERE pid=$PATIENT_PID AND type IN ('care_plan', 'goal', 'intervention', 'health_concern')" 2>/dev/null || echo "0")
echo "$INITIAL_LISTS" > /tmp/initial_lists_count.txt
echo "Initial care plan lists count: $INITIAL_LISTS"

# Count total list entries for the patient (backup metric)
INITIAL_ALL_LISTS=$(docker exec openemr-mysql mysql -u openemr -popenemr openemr -N -e \
    "SELECT COUNT(*) FROM lists WHERE pid=$PATIENT_PID" 2>/dev/null || echo "0")
echo "$INITIAL_ALL_LISTS" > /tmp/initial_all_lists_count.txt
echo "Initial total lists count: $INITIAL_ALL_LISTS"

# Clean up any previous task artifacts
rm -f /tmp/create_careplan_result.json 2>/dev/null || true

# Ensure Firefox is running with OpenEMR login page
echo "Setting up Firefox..."
pkill -f firefox 2>/dev/null || true
sleep 2

# Start Firefox to login page
OPENEMR_URL="http://localhost/interface/login/login.php?site=default"
su - ga -c "DISPLAY=:1 firefox '$OPENEMR_URL' > /tmp/firefox_careplan.log 2>&1 &"
sleep 5

# Wait for Firefox window
echo "Waiting for Firefox window..."
for i in {1..30}; do
    if DISPLAY=:1 wmctrl -l 2>/dev/null | grep -qi "firefox\|mozilla\|OpenEMR"; then
        echo "Firefox window detected after ${i}s"
        break
    fi
    sleep 1
done

# Maximize Firefox
DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true

# Focus Firefox
WID=$(DISPLAY=:1 wmctrl -l | grep -i "firefox\|mozilla" | head -1 | awk '{print $1}')
if [ -n "$WID" ]; then
    DISPLAY=:1 wmctrl -ia "$WID" 2>/dev/null || true
fi

# Take initial screenshot for audit
sleep 2
DISPLAY=:1 scrot /tmp/task_initial_state.png 2>/dev/null || \
    DISPLAY=:1 import -window root /tmp/task_initial_state.png 2>/dev/null || true

if [ -f /tmp/task_initial_state.png ]; then
    SIZE=$(stat -c %s /tmp/task_initial_state.png 2>/dev/null || echo "0")
    echo "Initial screenshot captured: ${SIZE} bytes"
else
    echo "WARNING: Could not capture initial screenshot"
fi

echo ""
echo "=== Create Care Plan Task Setup Complete ==="
echo ""
echo "Patient: $PATIENT_NAME (PID: $PATIENT_PID)"
echo "Condition: Type 2 Diabetes Mellitus"
echo ""
echo "Task: Create a care plan with:"
echo "  - Health Concern: Type 2 Diabetes Mellitus"
echo "  - Goal: Reduce HbA1c to below 7.0% within 6 months"
echo "  - Intervention: Medication adherence counseling and monthly blood glucose monitoring"
echo ""
echo "Login: admin / pass"
echo ""