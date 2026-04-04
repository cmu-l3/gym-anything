#!/bin/bash
# Setup: register_patient task
# Ensures Meredith Voss does NOT already exist, then opens Firefox on registration form.

echo "=== Setting up register_patient task ==="
source /workspace/scripts/task_utils.sh

# Record task start time (anti-gaming)
date +%s > /tmp/task_start_timestamp

# Remove any pre-existing Meredith Voss to allow re-runs
echo "Checking for pre-existing Meredith Voss..."
EXISTING=$(omrs_get "/patient?q=Meredith+Voss&v=default" | \
    python3 -c "import sys,json; r=json.load(sys.stdin); [print(p['uuid']) for p in r.get('results',[])]" 2>/dev/null || true)
if [ -n "$EXISTING" ]; then
    echo "Voiding pre-existing Meredith Voss records..."
    while IFS= read -r uuid; do
        [ -n "$uuid" ] && omrs_delete "/patient/$uuid" > /dev/null || true
    done <<< "$EXISTING"
fi

# Record initial patient count
INITIAL_COUNT=$(omrs_get "/patient?q=&v=count&limit=1" | \
    python3 -c "import sys,json; r=json.load(sys.stdin); print(r.get('totalCount',0))" 2>/dev/null || echo "0")
echo "$INITIAL_COUNT" > /tmp/initial_patient_count
echo "Initial patient count: $INITIAL_COUNT"

# Open Firefox on the patient registration form
ensure_openmrs_logged_in "http://localhost/openmrs/spa/patient-registration"

# Take initial screenshot
take_screenshot /tmp/task_start_screenshot.png

echo ""
echo "=== register_patient task setup complete ==="
echo ""
echo "TASK: Register a new patient with these details:"
echo "  Given name:  Meredith"
echo "  Family name: Voss"
echo "  DOB:         1989-03-22"
echo "  Sex:         Female"
echo "  Address:     407 Cascade Way, Seattle, Washington"
echo ""
echo "Login: admin / Admin123"
