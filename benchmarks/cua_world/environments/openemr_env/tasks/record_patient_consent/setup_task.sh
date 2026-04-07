#!/bin/bash
# Setup script for Record Patient Consent task

echo "=== Setting up Record Patient Consent Task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Target patient
PATIENT_PID=3
PATIENT_NAME="Jayson Fadel"

# Record task start timestamp (critical for anti-gaming)
TASK_START=$(date +%s)
echo "$TASK_START" > /tmp/task_start_time.txt
echo "Task start timestamp: $TASK_START"

# Verify patient exists
echo "Verifying patient $PATIENT_NAME (pid=$PATIENT_PID) exists..."
PATIENT_CHECK=$(openemr_query "SELECT pid, fname, lname, DOB FROM patient_data WHERE pid=$PATIENT_PID" 2>/dev/null)
if [ -z "$PATIENT_CHECK" ]; then
    echo "ERROR: Patient not found in database!"
    exit 1
fi
echo "Patient found: $PATIENT_CHECK"

# Record initial document count for this patient
echo "Recording initial document counts..."

# Check documents table
INITIAL_DOC_COUNT=$(openemr_query "SELECT COUNT(*) FROM documents WHERE foreign_id=$PATIENT_PID" 2>/dev/null || echo "0")
echo "$INITIAL_DOC_COUNT" > /tmp/initial_doc_count.txt
echo "Initial document count (documents table): $INITIAL_DOC_COUNT"

# Check onsite_documents table
INITIAL_ONSITE_COUNT=$(openemr_query "SELECT COUNT(*) FROM onsite_documents WHERE pid=$PATIENT_PID" 2>/dev/null || echo "0")
echo "$INITIAL_ONSITE_COUNT" > /tmp/initial_onsite_count.txt
echo "Initial onsite document count: $INITIAL_ONSITE_COUNT"

# Check forms table for any consent-related forms
INITIAL_FORMS_COUNT=$(openemr_query "SELECT COUNT(*) FROM forms WHERE pid=$PATIENT_PID" 2>/dev/null || echo "0")
echo "$INITIAL_FORMS_COUNT" > /tmp/initial_forms_count.txt
echo "Initial forms count: $INITIAL_FORMS_COUNT"

# List existing documents for debugging
echo ""
echo "=== Existing documents for patient ==="
openemr_query "SELECT d.id, d.name, d.type, c.name as category FROM documents d LEFT JOIN categories_to_documents cd ON d.id=cd.document_id LEFT JOIN categories c ON cd.category_id=c.id WHERE d.foreign_id=$PATIENT_PID ORDER BY d.id DESC LIMIT 5" 2>/dev/null || echo "No documents found"
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

# Take initial screenshot for verification
echo "Capturing initial screenshot..."
sleep 1
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || \
    DISPLAY=:1 import -window root /tmp/task_initial.png 2>/dev/null || true

if [ -f /tmp/task_initial.png ]; then
    SIZE=$(stat -c %s /tmp/task_initial.png 2>/dev/null || echo "0")
    echo "Initial screenshot captured: ${SIZE} bytes"
else
    echo "WARNING: Could not capture initial screenshot"
fi

echo ""
echo "=== Record Patient Consent Task Setup Complete ==="
echo ""
echo "Task Instructions:"
echo "  Patient: $PATIENT_NAME (PID: $PATIENT_PID, DOB: 1992-06-30)"
echo ""
echo "  1. Log in to OpenEMR"
echo "     - Username: admin"
echo "     - Password: pass"
echo ""
echo "  2. Search for and select patient Jayson Fadel"
echo ""
echo "  3. Navigate to Documents section"
echo ""
echo "  4. Create a new consent document with:"
echo "     - Type: General Consent to Treatment"
echo "     - Note: Patient consents to routine examination, treatment,"
echo "             and diagnostic procedures as medically indicated."
echo ""
echo "  5. Save the consent record"
echo ""