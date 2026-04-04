#!/bin/bash
set -e
echo "=== Setting up Configure Facility Details Task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time for anti-gaming verification
date +%s > /tmp/task_start_time.txt

# Ensure LibreHealth EHR is running and accessible
wait_for_librehealth 120

# 1. Reset Facility ID 1 to a generic state to ensure the agent must make changes
# We use the utility function to execute the SQL update
echo "Resetting facility ID 1 to generic placeholder..."
librehealth_query "UPDATE facility SET name='Your Clinic Name Here', federal_ein='', email='', website='', phone='', billing_location=0 WHERE id=1;"

# 2. Record initial state for verification (anti-gaming)
# We save the initial values to compare later
echo "Recording initial database state..."
librehealth_query "SELECT name, federal_ein, email, website, phone, billing_location FROM facility WHERE id=1" > /tmp/initial_facility_state.txt
cat /tmp/initial_facility_state.txt

# 3. Prepare Firefox
# Kill any existing instances and start fresh at the login page
restart_firefox "http://localhost:8000/interface/login/login.php?site=default"

# 4. Capture initial screenshot for evidence
echo "Capturing initial state screenshot..."
take_screenshot /tmp/task_initial.png

echo "=== Task Setup Complete ==="