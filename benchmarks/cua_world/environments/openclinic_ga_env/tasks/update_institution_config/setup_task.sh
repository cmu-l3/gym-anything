#!/bin/bash
# Setup script for update_institution_config task

echo "=== Setting up Update Institution Config Task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start timestamp for anti-gaming (DB updates must happen after this)
record_task_start /tmp/task_start_timestamp

# Ensure OpenClinic is running and accessible
echo "Checking OpenClinic availability..."
if ! curl -s "http://localhost:10088/openclinic" > /dev/null; then
    echo "OpenClinic not responding, attempting start..."
    if [ -f /opt/openclinic/start_openclinic ]; then
        /opt/openclinic/start_openclinic 2>/dev/null || true
        sleep 10
    fi
fi

# Ensure Firefox is running and focused on OpenClinic
# We want the agent to start at the login screen or main menu
ensure_openclinic_browser "http://localhost:10088/openclinic"
sleep 3

# Capture initial screenshot
take_screenshot /tmp/task_initial_state.png

# Capture initial config state (if possible) for debugging
# This dumps all parameters that might be related to institution/hospital
echo "Capturing initial DB state..."
$MYSQL_BIN $MYSQL_OPTS ocadmin_dbo -N -e "SELECT * FROM OC_PARAMETERS WHERE parameter LIKE '%institution%' OR parameter LIKE '%hospital%' OR parameter LIKE '%name%'" > /tmp/initial_db_config.txt 2>/dev/null || true

echo "=== Setup Complete ==="
echo "Task: Update Institution Configuration"
echo "Target Values:"
echo "  Name: Saint Helena Regional Medical Center"
echo "  Address: 450 Commonwealth Boulevard, Richmond, VA 23219"
echo "  Phone: +1-804-555-0142"
echo "  Fax: +1-804-555-0143"