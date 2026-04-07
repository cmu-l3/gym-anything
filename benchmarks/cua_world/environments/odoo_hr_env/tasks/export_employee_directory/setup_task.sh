#!/bin/bash
set -e
echo "=== Setting up export_employee_directory task ==="

source /workspace/scripts/task_utils.sh

# Record task start time for anti-gaming (file modification check)
date +%s > /tmp/task_start_time.txt

# Clear Downloads directory to ensure we identify the correct new file
rm -f /home/ga/Downloads/*.xlsx
rm -f /home/ga/Downloads/*.xls
rm -f /home/ga/Downloads/*.csv
echo "Cleared ~/Downloads directory"

# Ensure Odoo is running
if ! docker ps | grep -q "odoo-odoo"; then
    echo "Starting Odoo services..."
    /workspace/scripts/setup_odoo.sh
fi

# Launch Firefox and navigate to Employees list
# We use the action ID for the Employee list view to ensure correct starting point
echo "Launching Firefox to Employees list..."
ensure_firefox "http://localhost:8069/web#action=hr.open_view_employee_list_my"

# Wait for page load and take initial screenshot
sleep 5
take_screenshot /tmp/task_initial.png

echo "=== Setup complete ==="