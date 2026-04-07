#!/bin/bash
# Setup script for create_encounter_type task

echo "=== Setting up Create Encounter Type Task ==="
source /workspace/scripts/task_utils.sh

# 1. Record task start time for anti-gaming verification
date +%s > /tmp/task_start_time.txt

# 2. Cleanup: Retire/Rename any existing Encounter Type with the target name
# This ensures the agent must actually create a new one.
echo "Cleaning up existing 'Telehealth Intake' encounter types..."
omrs_db_query "UPDATE encounter_type SET name = CONCAT('Retired_', uuid), retired = 1, retire_reason = 'Task Setup Cleanup' WHERE name = 'Telehealth Intake' AND retired = 0;" 2>/dev/null || true

# 3. Create the ticket details file on Desktop
echo "Creating ticket details file..."
mkdir -p /home/ga/Desktop
cat > /home/ga/Desktop/ticket_details.txt << EOF
TICKET #49201
PRIORITY: Normal
REQUESTER: Dr. A. Smith

SUBJECT: New Encounter Type for Remote Visits

Please configure the following new Encounter Type in the system for our upcoming pilot:

Name: Telehealth Intake
Description: Initial patient assessment conducted via remote video connection.

This is required for the new billing module to distinguish remote vs in-person intakes.
EOF
chown ga:ga /home/ga/Desktop/ticket_details.txt

# 4. Open Firefox to O3 Home
# We start at the SPA home. The agent must figure out how to get to Legacy Admin 
# (usually via System Administration app or direct URL navigation if they are smart).
echo "Launching Firefox..."
ensure_openmrs_logged_in "http://localhost/openmrs/spa/home"

# 5. Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup Complete ==="