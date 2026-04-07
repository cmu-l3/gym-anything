#!/bin/bash
echo "=== Setting up implement_address_audit_trigger task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Ensure MySQL is running and ready
systemctl start mysql 2>/dev/null || service mysql start 2>/dev/null || true
wait_for_mysql() {
    for i in {1..30}; do
        if mysqladmin ping -h localhost --silent 2>/dev/null; then
            return 0
        fi
        sleep 1
    done
    return 1
}
wait_for_mysql

# Clean state: Remove the trigger and table if they already exist from a previous run
echo "Cleaning up previous attempts..."
mysql -u root DrTuxTest -e "DROP TRIGGER IF EXISTS trg_audit_address_update;" 2>/dev/null || true
mysql -u root DrTuxTest -e "DROP TABLE IF EXISTS address_audit_log;" 2>/dev/null || true

# Remove the output file if it exists
rm -f /home/ga/audit_implementation.sql

# Ensure MedinTux Manager is running (to simulate realistic environment)
# This provides the context that the app is "live" while we modify the DB
launch_medintux_manager

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="