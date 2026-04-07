#!/bin/bash
set -e
echo "=== Setting up update_appointment_service task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time for anti-gaming verification
date +%s > /tmp/task_start_time.txt

# ── 1. Create/Reset the Pre-requisite Appointment Service ────────────────────
echo "Seeding 'Dermatology Consult' service..."

# We use direct DB queries to ensure a clean state regardless of UI/API quirks
# Check if service exists
SERVICE_UUID=$(omrs_db_query "SELECT uuid FROM appointment_service WHERE name = 'Dermatology Consult' AND voided = 0 LIMIT 1;")

if [ -n "$SERVICE_UUID" ]; then
    echo "  Service already exists ($SERVICE_UUID). Resetting values..."
    # Reset to initial state: 15 mins, old description, clear date_changed to ensure we detect new edits
    omrs_db_query "UPDATE appointment_service SET duration_mins = 15, description = 'Standard skin check', date_changed = NULL WHERE uuid = '$SERVICE_UUID';"
else
    echo "  Creating new service..."
    # Generate a random UUID
    UUID=$(cat /proc/sys/kernel/random/uuid)
    # Insert new service: 15 mins, old description
    # Note: creator=1 is typically admin
    omrs_db_query "INSERT INTO appointment_service (uuid, name, duration_mins, description, voided, creator, date_created) VALUES ('$UUID', 'Dermatology Consult', 15, 'Standard skin check', 0, 1, NOW());"
fi

# ── 2. Ensure Browser is Ready ───────────────────────────────────────────────
# We navigate to the home page. The agent must find the Appointments app.
echo "Launching OpenMRS..."
ensure_openmrs_logged_in "$SPA_URL/home"

# Take initial screenshot
take_screenshot /tmp/task_initial_state.png

echo "=== Task setup complete ==="
echo "Task: Update 'Dermatology Consult' service"
echo "  - New Duration: 45 minutes"
echo "  - New Description: Comprehensive initial skin assessment and biopsy planning"