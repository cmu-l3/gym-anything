#!/bin/bash
# Setup script for Generate Encounter Report PDF task

echo "=== Setting up Generate Encounter Report Task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Target patient
PATIENT_PID=3
PATIENT_NAME="Jayson Fadel"
OUTPUT_PATH="/home/ga/Documents/encounter_report.pdf"

# Record task start timestamp (CRITICAL for anti-gaming)
date +%s > /tmp/task_start_time.txt
echo "Task start timestamp: $(cat /tmp/task_start_time.txt)"

# Ensure output directory exists with correct permissions
echo "Setting up output directory..."
mkdir -p /home/ga/Documents
mkdir -p /home/ga/Downloads
chown -R ga:ga /home/ga/Documents
chown -R ga:ga /home/ga/Downloads

# Remove any existing report files (clean slate)
echo "Removing any existing report files..."
rm -f /home/ga/Documents/encounter_report.pdf 2>/dev/null || true
rm -f /home/ga/Documents/*.pdf 2>/dev/null || true
rm -f /home/ga/Downloads/*.pdf 2>/dev/null || true

# Verify patient exists in database
echo "Verifying patient $PATIENT_NAME (pid=$PATIENT_PID) exists..."
PATIENT_CHECK=$(openemr_query "SELECT pid, fname, lname FROM patient_data WHERE pid=$PATIENT_PID" 2>/dev/null)
if [ -z "$PATIENT_CHECK" ]; then
    echo "ERROR: Patient not found in database!"
    exit 1
fi
echo "Patient found: $PATIENT_CHECK"

# Verify patient has encounters
echo "Verifying patient has encounters..."
ENCOUNTER_COUNT=$(openemr_query "SELECT COUNT(*) FROM form_encounter WHERE pid=$PATIENT_PID" 2>/dev/null || echo "0")
echo "Patient has $ENCOUNTER_COUNT encounter(s)"

if [ "$ENCOUNTER_COUNT" -eq "0" ]; then
    echo "WARNING: Patient has no encounters - task may not be completable"
fi

# Get the most recent encounter info for logging
ENCOUNTER_INFO=$(openemr_query "SELECT id, date, reason FROM form_encounter WHERE pid=$PATIENT_PID ORDER BY date DESC LIMIT 1" 2>/dev/null)
echo "Most recent encounter: $ENCOUNTER_INFO"

# Configure Firefox to download PDFs to Documents folder
echo "Configuring Firefox PDF settings..."
FIREFOX_PREFS="/home/ga/.mozilla/firefox/default-release/user.js"
if [ -f "$FIREFOX_PREFS" ]; then
    cat >> "$FIREFOX_PREFS" << 'PREFS'
// PDF download configuration for encounter report task
user_pref("browser.download.dir", "/home/ga/Documents");
user_pref("browser.download.folderList", 2);
user_pref("browser.download.useDownloadDir", true);
user_pref("browser.download.manager.showWhenStarting", false);
user_pref("browser.helperApps.neverAsk.saveToDisk", "application/pdf,application/x-pdf");
user_pref("pdfjs.disabled", false);
user_pref("print.print_to_file", true);
user_pref("print.print_to_filename", "/home/ga/Documents/encounter_report.pdf");
PREFS
    chown ga:ga "$FIREFOX_PREFS"
fi

# Ensure Firefox is running on OpenEMR login page
echo "Ensuring Firefox is running..."
OPENEMR_URL="http://localhost/interface/login/login.php?site=default"

# Kill existing Firefox instances for a clean start
pkill -f firefox 2>/dev/null || true
sleep 2

# Start Firefox
echo "Starting Firefox..."
su - ga -c "DISPLAY=:1 firefox '$OPENEMR_URL' > /tmp/firefox_task.log 2>&1 &"
sleep 5

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
sleep 2
take_screenshot /tmp/task_initial_state.png
echo "Initial screenshot saved to /tmp/task_initial_state.png"

echo ""
echo "=== Generate Encounter Report Task Setup Complete ==="
echo ""
echo "Task Instructions:"
echo "  1. Log in to OpenEMR"
echo "     - Username: admin"
echo "     - Password: pass"
echo ""
echo "  2. Find patient: $PATIENT_NAME (PID: $PATIENT_PID)"
echo ""
echo "  3. Open the patient's encounter history"
echo ""
echo "  4. Select the encounter from 2019-10-15 (or most recent)"
echo ""
echo "  5. Generate a report/PDF of the encounter"
echo ""
echo "  6. Save the PDF to: $OUTPUT_PATH"
echo ""
echo "Note: Use File > Save As or Ctrl+S to save the PDF"
echo ""