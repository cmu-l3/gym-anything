#!/bin/bash
# Setup script for Document Flu Vaccination Task

echo "=== Setting up Document Flu Vaccine Task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Target patient
PATIENT_PID=3
PATIENT_NAME="Jayson Fadel"

# Record task start timestamp (critical for anti-gaming)
date +%s > /tmp/task_start_time.txt
echo "Task start timestamp: $(cat /tmp/task_start_time.txt)"

# Verify patient exists
echo "Verifying patient $PATIENT_NAME (pid=$PATIENT_PID) exists..."
PATIENT_CHECK=$(openemr_query "SELECT pid, fname, lname, DOB FROM patient_data WHERE pid=$PATIENT_PID" 2>/dev/null)
if [ -z "$PATIENT_CHECK" ]; then
    echo "ERROR: Patient not found in database!"
    exit 1
fi
echo "Patient found: $PATIENT_CHECK"

# Record initial immunization count for this patient
echo "Recording initial immunization count..."
INITIAL_IMM_COUNT=$(openemr_query "SELECT COUNT(*) FROM immunizations WHERE patient_id=$PATIENT_PID" 2>/dev/null || echo "0")
echo "$INITIAL_IMM_COUNT" > /tmp/initial_immunization_count.txt
echo "Initial immunization count for patient: $INITIAL_IMM_COUNT"

# Record total immunizations table count (backup metric)
TOTAL_IMM_COUNT=$(openemr_query "SELECT COUNT(*) FROM immunizations" 2>/dev/null || echo "0")
echo "$TOTAL_IMM_COUNT" > /tmp/initial_total_immunizations.txt
echo "Total immunizations in database: $TOTAL_IMM_COUNT"

# Show existing immunizations for this patient (debug info)
echo ""
echo "=== Existing immunizations for patient ==="
openemr_query "SELECT id, administered_date, manufacturer, lot_number FROM immunizations WHERE patient_id=$PATIENT_PID ORDER BY id DESC LIMIT 5" 2>/dev/null || echo "None found"
echo "=== End existing immunizations ==="
echo ""

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
echo "=== Document Flu Vaccine Task Setup Complete ==="
echo ""
echo "Patient: $PATIENT_NAME (PID: $PATIENT_PID, DOB: 1992-06-30)"
echo ""
echo "Task: Document the following flu vaccination:"
echo "  - Vaccine: Influenza, seasonal, injectable"
echo "  - Date Administered: Today"
echo "  - Manufacturer: Sanofi Pasteur"
echo "  - Lot Number: FL2024-3892"
echo "  - Expiration: 2025-06-30"
echo "  - Site: Left Deltoid"
echo "  - Route: Intramuscular (IM)"
echo "  - Dosage: 0.5 mL"
echo "  - Notes: Annual flu vaccination - patient tolerated well"
echo ""
echo "Login credentials: admin / pass"
echo ""