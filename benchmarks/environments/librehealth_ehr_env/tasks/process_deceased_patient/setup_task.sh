#!/bin/bash
echo "=== Setting up Process Deceased Patient Task ==="

source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Ensure LibreHealth is running
wait_for_librehealth 60

# 1. Identify or Create Patient "Pedro Alva"
# We try to find him in NHANES data first
echo "Searching for patient Pedro Alva..."
PID=$(librehealth_query "SELECT pid FROM patient_data WHERE fname='Pedro' AND lname='Alva' LIMIT 1")

if [ -z "$PID" ]; then
    echo "Patient not found, creating Pedro Alva..."
    # Create patient via SQL to ensure clean state
    librehealth_query "INSERT INTO patient_data (fname, lname, sex, DOB, street, city, state, postal_code, phone_home) VALUES ('Pedro', 'Alva', 'Male', '1955-06-15', '123 Memory Lane', 'Austin', 'TX', '78701', '555-0199')"
    PID=$(librehealth_query "SELECT pid FROM patient_data WHERE fname='Pedro' AND lname='Alva' LIMIT 1")
fi

echo "Target Patient PID: $PID"
echo "$PID" > /tmp/target_pid.txt

# 2. Reset Patient State (Alive)
# Ensure deceased_date is NULL and deceased_reason is empty
librehealth_query "UPDATE patient_data SET deceased_date=NULL, deceased_reason='' WHERE pid='$PID'"

# 3. Inject Upcoming Appointment
# We calculate a date 5 days in the future
APPT_DATE=$(date -d "+5 days" +%Y-%m-%d)
APPT_TIME="10:00:00"
APPT_TITLE="Follow Up Visit"

# Remove any existing future appointments for this patient to avoid confusion
librehealth_query "DELETE FROM openemr_postcalendar_events WHERE pc_pid='$PID' AND pc_eventDate >= CURDATE()"

# Insert new appointment
# pc_apptstatus '-' usually means "None" or "Pending" in default OpenEMR/LibreHealth
# pc_catid 1 is typically "Office Visit" or "Established Patient"
echo "Creating appointment for $APPT_DATE at $APPT_TIME..."
librehealth_query "INSERT INTO openemr_postcalendar_events (pc_pid, pc_title, pc_eventDate, pc_eventTime, pc_duration, pc_apptstatus, pc_catid, pc_aid) VALUES ('$PID', '$APPT_TITLE', '$APPT_DATE', '$APPT_TIME', '900', '-', '1', '1')"

# Get the Event ID we just created
EID=$(librehealth_query "SELECT pc_eid FROM openemr_postcalendar_events WHERE pc_pid='$PID' AND pc_eventDate='$APPT_DATE' AND pc_eventTime='$APPT_TIME' LIMIT 1")
echo "$EID" > /tmp/target_eid.txt
echo "Created Appointment EID: $EID"

# Record initial appointment status for verification
INIT_STATUS=$(librehealth_query "SELECT pc_apptstatus FROM openemr_postcalendar_events WHERE pc_eid='$EID'")
echo "Initial Appointment Status: '$INIT_STATUS'"

# 4. Browser Setup
# Restart Firefox to the Calendar view or Patient Search
restart_firefox "http://localhost:8000/interface/main/calendar/index.php?module=PostCalendar&func=view"

# Capture initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup Complete ==="
echo "Patient: Pedro Alva (PID: $PID)"
echo "Appointment: $APPT_TITLE on $APPT_DATE (EID: $EID)"