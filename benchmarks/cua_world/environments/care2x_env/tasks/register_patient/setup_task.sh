#!/bin/bash
# Setup: register_patient task
# Ensures Elena Kowalski does NOT already exist, then opens Firefox on Care2x login page.

echo "=== Setting up register_patient task ==="
source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_timestamp

# Remove any pre-existing Elena Kowalski to allow re-runs
echo "Checking for pre-existing Elena Kowalski..."
EXISTING=$(care2x_query "SELECT pid FROM care_person WHERE name_first='Elena' AND name_last='Kowalski';" 2>/dev/null || true)
if [ -n "$EXISTING" ]; then
    echo "Removing pre-existing Elena Kowalski records..."
    care2x_query "DELETE FROM care_person WHERE name_first='Elena' AND name_last='Kowalski';" || true
fi

# Record initial patient count
INITIAL_COUNT=$(get_patient_count)
echo "$INITIAL_COUNT" > /tmp/initial_patient_count
echo "Initial patient count: $INITIAL_COUNT"

# Open Firefox on Care2x login page
ensure_firefox_on_url "$CARE2X_URL"

# Take initial screenshot
take_screenshot /tmp/task_start_screenshot.png

echo ""
echo "=== register_patient task setup complete ==="
echo ""
echo "TASK: Register a new patient with these details:"
echo "  First name:    Elena"
echo "  Last name:     Kowalski"
echo "  DOB:           1987-11-14"
echo "  Sex:           Female"
echo "  Address:       245 Birch Lane"
echo "  Zip code:      02134"
echo "  Phone:         617-555-0198"
echo "  Civil status:  Married"
echo ""
echo "Login: admin / care2x_admin"
