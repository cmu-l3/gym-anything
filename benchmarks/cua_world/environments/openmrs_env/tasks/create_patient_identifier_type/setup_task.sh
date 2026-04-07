#!/bin/bash
# Setup: create_patient_identifier_type task
# Ensures the "National ART Number" ID type does NOT exist before starting.

echo "=== Setting up create_patient_identifier_type task ==="
source /workspace/scripts/task_utils.sh

# Record task start time (anti-gaming)
date +%s > /tmp/task_start_timestamp

# Check for pre-existing "National ART Number" and purge it if found
echo "Checking for existing 'National ART Number'..."
EXISTING_UUID=$(omrs_get "/patientidentifiertype?q=National+ART+Number&v=default" | \
    python3 -c "import sys,json; r=json.load(sys.stdin); print(r['results'][0]['uuid'] if r.get('results') else '')" 2>/dev/null || true)

if [ -n "$EXISTING_UUID" ]; then
    echo "Purging existing definition ($EXISTING_UUID) to ensure clean state..."
    # Purge (hard delete) so it can be recreated with the same name
    omrs_delete "/patientidentifiertype/$EXISTING_UUID?purge=true"
    sleep 2
fi

# Double check it's gone
CHECK_UUID=$(omrs_get "/patientidentifiertype?q=National+ART+Number&v=default" | \
    python3 -c "import sys,json; r=json.load(sys.stdin); print(r['results'][0]['uuid'] if r.get('results') else '')" 2>/dev/null || true)

if [ -n "$CHECK_UUID" ]; then
    echo "WARNING: Failed to purge existing identifier type. Task may fail verification."
else
    echo "Clean state verified."
fi

# Ensure browser is open and logged in (start at home page)
# We start at Home so agent has to find System Admin / Settings
ensure_openmrs_logged_in "http://localhost/openmrs/spa/home"

# Take initial screenshot
take_screenshot /tmp/task_start_screenshot.png

echo ""
echo "=== create_patient_identifier_type setup complete ==="
echo ""
echo "TASK: Create Patient Identifier Type 'National ART Number'"
echo "  - Unique: Yes"
echo "  - Required: No"
echo "  - Min Length: 4"
echo "  - Max Length: 15"
echo ""
echo "Login: admin / Admin123"