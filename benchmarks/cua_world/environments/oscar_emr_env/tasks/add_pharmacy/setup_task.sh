#!/bin/bash
# Setup script for Add Pharmacy task in OSCAR EMR

echo "=== Setting up Add Pharmacy Task ==="

source /workspace/scripts/task_utils.sh

# 1. Clean up any previous runs (ensure pharmacy doesn't exist)
echo "Cleaning up any pre-existing records for Lakeshore Compounding Pharmacy..."
oscar_query "DELETE FROM pharmacyInfo WHERE name LIKE '%Lakeshore%Compounding%'" 2>/dev/null || true

# 2. Record initial state for anti-gaming verification
TASK_START=$(date +%s)
echo "$TASK_START" > /tmp/task_start_timestamp

INITIAL_COUNT=$(oscar_query "SELECT COUNT(*) FROM pharmacyInfo" || echo "0")
echo "$INITIAL_COUNT" > /tmp/initial_pharmacy_count
echo "Initial pharmacy count: $INITIAL_COUNT"

# 3. Ensure Firefox is open on the login page
ensure_firefox_on_oscar

# 4. Take initial screenshot
take_screenshot /tmp/task_initial_screenshot.png

echo ""
echo "=== Add Pharmacy Task Setup Complete ==="
echo ""
echo "TASK: Add 'Lakeshore Compounding Pharmacy' to the system."
echo "Login: oscardoc / oscar / PIN: 1117"
echo ""