#!/bin/bash
# Setup script for Record Patient SOGI Task

echo "=== Setting up Record Patient SOGI Task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Target patient
PATIENT_PID=6
PATIENT_NAME="Truman Crooks"

# Record task start timestamp for anti-gaming verification
date +%s > /tmp/task_start_timestamp
echo "Task start timestamp: $(cat /tmp/task_start_timestamp)"

# Verify patient exists
echo "Verifying patient $PATIENT_NAME (pid=$PATIENT_PID) exists..."
PATIENT_CHECK=$(openemr_query "SELECT pid, fname, lname, DOB, sex FROM patient_data WHERE pid=$PATIENT_PID" 2>/dev/null)
if [ -z "$PATIENT_CHECK" ]; then
    echo "ERROR: Patient not found in database!"
    exit 1
fi
echo "Patient found: $PATIENT_CHECK"

# Record initial SOGI values for verification
echo "Recording initial SOGI state..."
INITIAL_SOGI=$(openemr_query "SELECT sexual_orientation, gender_identity, sex FROM patient_data WHERE pid=$PATIENT_PID" 2>/dev/null)
echo "$INITIAL_SOGI" > /tmp/initial_sogi_state
echo "Initial SOGI state: $INITIAL_SOGI"

# Record the date_modified timestamp before task
INITIAL_MODIFIED=$(openemr_query "SELECT UNIX_TIMESTAMP(date) as modified_ts FROM patient_data WHERE pid=$PATIENT_PID" 2>/dev/null)
echo "$INITIAL_MODIFIED" > /tmp/initial_modified_timestamp
echo "Initial modified timestamp: $INITIAL_MODIFIED"

# Verify SOGI list options exist in the system
echo "Checking SOGI list options availability..."
SO_OPTIONS=$(openemr_query "SELECT COUNT(*) FROM list_options WHERE list_id='sexual_orientation'" 2>/dev/null || echo "0")
GI_OPTIONS=$(openemr_query "SELECT COUNT(*) FROM list_options WHERE list_id='gender_identity'" 2>/dev/null || echo "0")
echo "Sexual orientation options: $SO_OPTIONS"
echo "Gender identity options: $GI_OPTIONS"

# If SOGI lists don't exist, we need to create them
if [ "$SO_OPTIONS" -eq "0" ]; then
    echo "Creating sexual_orientation list options..."
    openemr_query "INSERT IGNORE INTO list_options (list_id, option_id, title, seq, is_default, option_value) VALUES 
        ('sexual_orientation', 'straight', 'Straight or heterosexual', 10, 0, 0),
        ('sexual_orientation', 'lesbian', 'Lesbian, gay, or homosexual', 20, 0, 0),
        ('sexual_orientation', 'bisexual', 'Bisexual', 30, 0, 0),
        ('sexual_orientation', 'something_else', 'Something else', 40, 0, 0),
        ('sexual_orientation', 'dont_know', 'Don\\'t know', 50, 0, 0),
        ('sexual_orientation', 'choose_not_to_disclose', 'Choose not to disclose', 60, 0, 0)" 2>/dev/null || true
fi

if [ "$GI_OPTIONS" -eq "0" ]; then
    echo "Creating gender_identity list options..."
    openemr_query "INSERT IGNORE INTO list_options (list_id, option_id, title, seq, is_default, option_value) VALUES 
        ('gender_identity', 'male', 'Identifies as Male', 10, 0, 0),
        ('gender_identity', 'female', 'Identifies as Female', 20, 0, 0),
        ('gender_identity', 'transgender_male', 'Transgender Male/Female-to-Male', 30, 0, 0),
        ('gender_identity', 'transgender_female', 'Transgender Female/Male-to-Female', 40, 0, 0),
        ('gender_identity', 'genderqueer', 'Genderqueer/Non-binary', 50, 0, 0),
        ('gender_identity', 'other', 'Additional gender category', 60, 0, 0),
        ('gender_identity', 'choose_not_to_disclose', 'Choose not to disclose', 70, 0, 0)" 2>/dev/null || true
fi

# Ensure the lists are registered in the lists table
openemr_query "INSERT IGNORE INTO list_options (list_id, option_id, title, seq) VALUES ('lists', 'sexual_orientation', 'Sexual Orientation', 0)" 2>/dev/null || true
openemr_query "INSERT IGNORE INTO list_options (list_id, option_id, title, seq) VALUES ('lists', 'gender_identity', 'Gender Identity', 0)" 2>/dev/null || true

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

# Take initial screenshot for audit verification
take_screenshot /tmp/task_initial.png
echo "Initial screenshot saved to /tmp/task_initial.png"

echo ""
echo "=== Record Patient SOGI Task Setup Complete ==="
echo ""
echo "Task Instructions:"
echo "  1. Log in to OpenEMR (Username: admin, Password: pass)"
echo ""
echo "  2. Search for patient: Truman Crooks (DOB: 1995-08-04)"
echo ""
echo "  3. Open patient demographics and locate SOGI fields"
echo ""
echo "  4. Record the following SOGI data:"
echo "     - Sexual Orientation: Bisexual"
echo "     - Gender Identity: Identifies as Male"
echo "     - Verify Sex: Male"
echo ""
echo "  5. Save the demographic changes"
echo ""
echo "Note: SOGI fields may be in a 'Choices' or expandable section"
echo ""