#!/bin/bash
echo "=== Setting up update_patient_demographics task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Ensure MySQL is running
systemctl start mysql 2>/dev/null || service mysql start 2>/dev/null || true
sleep 3

# Kill any existing MedinTux instance
pkill -f "Manager.exe" 2>/dev/null || true
pkill -f "wine" 2>/dev/null || true
sleep 2

# Enable general log for anti-gaming detection (to check for direct SQL injection later)
mysql -u root -e "SET GLOBAL general_log = 'ON'; SET GLOBAL general_log_file = '/tmp/mysql_general.log';" 2>/dev/null || true

# Clean up any previous test patient to ensure idempotency
echo "Cleaning up previous patient data..."
delete_patient "MARTINEAU" "Hélène" 2>/dev/null || true
delete_patient "MARTINEAU" "Helene" 2>/dev/null || true

# Generate a consistent GUID for this run
PATIENT_GUID="TASK-UPD-$(date +%s)-$(head -c 4 /dev/urandom | xxd -p)"
echo "$PATIENT_GUID" > /tmp/task_patient_guid.txt

# Insert patient with OLD demographics
# Address: 15 Rue de la Paix, 75002 Paris
# Phone: 01 42 65 78 90
echo "Inserting patient with OLD data..."
insert_patient "$PATIENT_GUID" "MARTINEAU" "Hélène" "1978-06-14" "F" "Mme" \
    "15 Rue de la Paix" "75002" "Paris" "01 42 65 78 90" "2780675002123"

# Verify insertion
VERIFY_ADDR=$(mysql -u root DrTuxTest -N -e "SELECT FchPat_Adresse FROM fchpat WHERE FchPat_GUID_Doss='$PATIENT_GUID'" 2>/dev/null)
if [ -z "$VERIFY_ADDR" ]; then
    echo "ERROR: Failed to insert initial patient data!"
    exit 1
fi
echo "Patient inserted successfully. Address: $VERIFY_ADDR"

# Launch MedinTux Manager
# This utility function handles Qt DLL extraction and window waiting
launch_medintux_manager

# Take initial screenshot
take_screenshot /tmp/task_initial_state.png

echo "=== Task setup complete ==="