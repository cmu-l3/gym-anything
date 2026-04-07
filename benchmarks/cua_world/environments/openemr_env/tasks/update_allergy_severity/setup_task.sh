#!/bin/bash
# Setup script for Update Allergy Severity task

echo "=== Setting up Update Allergy Severity Task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Target patient
PATIENT_PID=3
PATIENT_NAME="Jayson Fadel"
ALLERGY_TITLE="Penicillin"
INITIAL_SEVERITY="mild"
INITIAL_REACTION="skin rash"

# Record task start timestamp for anti-gaming verification
date +%s > /tmp/task_start_timestamp
echo "Task start timestamp: $(cat /tmp/task_start_timestamp)"

# Verify patient exists
echo "Verifying patient $PATIENT_NAME (pid=$PATIENT_PID) exists..."
PATIENT_CHECK=$(openemr_query "SELECT pid, fname, lname FROM patient_data WHERE pid=$PATIENT_PID" 2>/dev/null)
if [ -z "$PATIENT_CHECK" ]; then
    echo "ERROR: Patient not found in database!"
    exit 1
fi
echo "Patient found: $PATIENT_CHECK"

# Check if penicillin allergy already exists for this patient
echo "Checking for existing Penicillin allergy..."
EXISTING_ALLERGY=$(openemr_query "SELECT id, title, severity_al, reaction FROM lists WHERE pid=$PATIENT_PID AND type='allergy' AND (LOWER(title) LIKE '%penicillin%') ORDER BY id DESC LIMIT 1" 2>/dev/null)

if [ -z "$EXISTING_ALLERGY" ]; then
    echo "No existing Penicillin allergy found. Creating initial allergy record..."
    # Insert the allergy with mild severity for the task
    openemr_query "INSERT INTO lists (date, type, title, begdate, severity_al, reaction, pid, user, groupname, activity) VALUES (NOW(), 'allergy', 'Penicillin', '2015-03-10', 'mild', 'skin rash', $PATIENT_PID, 'admin', 'Default', 1)" 2>/dev/null
    
    # Verify insertion
    EXISTING_ALLERGY=$(openemr_query "SELECT id, title, severity_al, reaction FROM lists WHERE pid=$PATIENT_PID AND type='allergy' AND (LOWER(title) LIKE '%penicillin%') ORDER BY id DESC LIMIT 1" 2>/dev/null)
    echo "Created allergy record: $EXISTING_ALLERGY"
else
    echo "Existing allergy found: $EXISTING_ALLERGY"
    
    # Extract allergy ID and reset to initial state (mild severity, skin rash)
    ALLERGY_ID=$(echo "$EXISTING_ALLERGY" | cut -f1)
    CURRENT_SEVERITY=$(echo "$EXISTING_ALLERGY" | cut -f3)
    
    if [ "$CURRENT_SEVERITY" != "$INITIAL_SEVERITY" ]; then
        echo "Resetting allergy to initial state (mild severity, skin rash)..."
        openemr_query "UPDATE lists SET severity_al='$INITIAL_SEVERITY', reaction='$INITIAL_REACTION' WHERE id=$ALLERGY_ID" 2>/dev/null
    fi
fi

# Record initial allergy state for verification comparison
echo "Recording initial allergy state..."
INITIAL_STATE=$(openemr_query "SELECT id, title, severity_al, reaction, UNIX_TIMESTAMP(modifydate) as mod_ts FROM lists WHERE pid=$PATIENT_PID AND type='allergy' AND (LOWER(title) LIKE '%penicillin%') ORDER BY id DESC LIMIT 1" 2>/dev/null)

# Save initial state to temp file
echo "$INITIAL_STATE" > /tmp/initial_allergy_state.txt
echo "Initial allergy state saved:"
cat /tmp/initial_allergy_state.txt

# Record initial allergy count to detect if new allergy was created instead of editing
INITIAL_ALLERGY_COUNT=$(openemr_query "SELECT COUNT(*) FROM lists WHERE pid=$PATIENT_PID AND type='allergy'" 2>/dev/null || echo "0")
echo "$INITIAL_ALLERGY_COUNT" > /tmp/initial_allergy_count.txt
echo "Initial allergy count for patient: $INITIAL_ALLERGY_COUNT"

# Ensure Firefox is running on OpenEMR login page
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

# Dismiss any popups
DISPLAY=:1 xdotool key Escape 2>/dev/null || true
sleep 0.5

# Take initial screenshot for audit verification
take_screenshot /tmp/task_initial_state.png
echo "Initial screenshot saved to /tmp/task_initial_state.png"

echo ""
echo "=== Update Allergy Severity Task Setup Complete ==="
echo ""
echo "Patient: $PATIENT_NAME (PID: $PATIENT_PID)"
echo "Existing Allergy: $ALLERGY_TITLE"
echo "Current Severity: $INITIAL_SEVERITY"
echo "Current Reaction: $INITIAL_REACTION"
echo ""
echo "Task: Update severity to 'severe' and reaction to 'anaphylaxis'"
echo ""
echo "IMPORTANT: Edit the EXISTING allergy record, do NOT create a new one!"
echo ""