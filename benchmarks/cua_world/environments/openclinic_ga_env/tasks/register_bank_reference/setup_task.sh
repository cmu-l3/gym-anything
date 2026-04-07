#!/bin/bash
set -e
echo "=== Setting up Register Bank Reference task ==="

# Source shared utilities for database connections
source /workspace/scripts/task_utils.sh

# 1. Record Task Start Time (Anti-gaming)
record_task_start /tmp/task_start_timestamp

# 2. Database Setup: Clean state
# Remove "Equity Bank" if it already exists to ensure the agent actually creates it
echo "Cleaning up any existing 'Equity Bank' records..."

# Check likely tables for banks in ocadmin_dbo
# Note: In OpenClinic, banks are often stored in OC_BANKS or similar reference tables
# We'll try to delete from common candidates
admin_query "DELETE FROM OC_BANKS WHERE OC_BANK_NAME='Equity Bank'" 2>/dev/null || true
admin_query "DELETE FROM Banks WHERE name='Equity Bank'" 2>/dev/null || true

# 3. Record Initial State
# Count existing banks to detect changes
INITIAL_COUNT=$(admin_query "SELECT COUNT(*) FROM OC_BANKS" 2>/dev/null || echo "0")
echo "$INITIAL_COUNT" > /tmp/initial_bank_count
echo "Initial bank count: $INITIAL_COUNT"

# 4. App Setup
# Ensure Firefox is running and at the login screen
ensure_openclinic_browser "http://localhost:10088/openclinic"

# 5. Capture Initial Evidence
take_screenshot /tmp/task_initial_screenshot.png

echo "=== Task Setup Complete ==="
echo "Target: Register 'Equity Bank' in the system."