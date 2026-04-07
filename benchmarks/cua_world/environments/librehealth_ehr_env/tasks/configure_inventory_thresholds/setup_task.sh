#!/bin/bash
set -e
echo "=== Setting up Configure Inventory Thresholds Task ==="

source /workspace/scripts/task_utils.sh

# Record task start time (for anti-gaming verification)
date +%s > /tmp/task_start_time.txt

# Ensure LibreHealth EHR is accessible
wait_for_librehealth 120

# 1. Enable Inventory/Dispensary Module Global Setting
echo "Enabling Drug Dispensary global setting..."
librehealth_query "UPDATE globals SET gl_value='1' WHERE gl_name='d_dispensary'"

# 2. Seed Target Drugs
# We use INSERT ... ON DUPLICATE KEY UPDATE to ensure they exist and reset values
echo "Seeding inventory data..."

# Drug 1: Ibuprofen 200mg (Reset reorder_point to 0)
librehealth_query "INSERT INTO drugs (name, ndc_number, form, size, unit, reorder_point, on_order)
VALUES ('Ibuprofen 200mg', '00001-0001-01', 1, 200, 1, 0, 500)
ON DUPLICATE KEY UPDATE reorder_point=0;"

# Drug 2: Metformin 500mg (Reset reorder_point to 0)
librehealth_query "INSERT INTO drugs (name, ndc_number, form, size, unit, reorder_point, on_order)
VALUES ('Metformin 500mg', '00002-0002-02', 1, 500, 1, 0, 300)
ON DUPLICATE KEY UPDATE reorder_point=0;"

# Record initial state for debugging/verification
INITIAL_STATE=$(librehealth_query "SELECT name, reorder_point FROM drugs WHERE name IN ('Ibuprofen 200mg', 'Metformin 500mg')")
echo "Initial DB State:"
echo "$INITIAL_STATE"

# 3. Prepare Browser
# Restart Firefox to ensure clean state at login page
restart_firefox "http://localhost:8000/interface/login/login.php?site=default"

# 4. Capture Evidence
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="