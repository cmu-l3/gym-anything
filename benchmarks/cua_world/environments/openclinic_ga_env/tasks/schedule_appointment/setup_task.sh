#!/bin/bash
echo "=== Setting up Schedule Appointment task ==="

source /workspace/scripts/task_utils.sh

record_task_start /tmp/task_start_timestamp

# Patient: Carlos Mendoza (personid=10002), seeded in ocadmin_dbo
PATIENT_ID=10002
PATIENT_NAME="CARLOS MENDOZA"
echo "Task patient: $PATIENT_NAME (ID: $PATIENT_ID)"

# Verify patient exists; re-seed if not
CARLOS_EXISTS=$(admin_query "SELECT COUNT(*) FROM adminview WHERE personid=$PATIENT_ID" | tr -d '[:space:]')
if [ "$CARLOS_EXISTS" = "0" ] || [ -z "$CARLOS_EXISTS" ]; then
    echo "Patient Carlos Mendoza not found — re-running seed..."
    /opt/openclinic/mysql5/bin/mysql -S /tmp/mysql5.sock -u root < /workspace/config/seed_data.sql 2>/dev/null || true
fi

echo "$PATIENT_ID" > /tmp/apt_task_patient_id

# Remove pre-existing "Diabetes follow-up" appointments for this patient (clean state)
clinical_query "DELETE FROM oc_planning WHERE OC_PLANNING_PATIENTID=$PATIENT_ID AND OC_PLANNING_DESCRIPTION LIKE '%Diabetes follow-up%'" 2>/dev/null || true

# Record baseline appointment count
INITIAL_APTS=$(clinical_query "SELECT COUNT(*) FROM oc_planning WHERE OC_PLANNING_DESCRIPTION LIKE '%Diabetes follow-up%'" | tr -d '[:space:]' || echo "0")
echo "$INITIAL_APTS" > /tmp/initial_appointment_count
echo "Baseline matching appointments: $INITIAL_APTS"

# Calculate and store tomorrow's date
TOMORROW=$(date -d "+1 day" +%Y-%m-%d)
echo "$TOMORROW" > /tmp/appointment_date
echo "Target appointment date: $TOMORROW"

# Launch Firefox at OpenClinic
ensure_openclinic_browser "http://localhost:10088/openclinic"
sleep 3

take_screenshot /tmp/task_initial_screenshot.png

echo ""
echo "=== Schedule Appointment task ready ==="
echo "Patient: $PATIENT_NAME (ID=$PATIENT_ID)"
echo "Date: $TOMORROW (tomorrow)"
echo "Type: Outpatient"
echo "Description: Diabetes follow-up consultation"
echo "Login: username=4, password=openclinic"
