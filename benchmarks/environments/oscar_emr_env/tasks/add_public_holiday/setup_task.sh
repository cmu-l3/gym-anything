#!/bin/bash
# Setup script for Add Public Holiday task

echo "=== Setting up Add Public Holiday Task ==="

source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Target holiday details
HOLIDAY_DATE="2026-05-18"
HOLIDAY_NAME="Victoria Day"

echo "Ensuring clean state for holiday: $HOLIDAY_NAME ($HOLIDAY_DATE)..."

# Delete the holiday if it already exists (to ensure agent actually adds it)
# The table is typically 'public_holiday' with columns 'date_holiday' and 'name'
oscar_query "DELETE FROM public_holiday WHERE date_holiday='$HOLIDAY_DATE'" 2>/dev/null || true
oscar_query "DELETE FROM public_holiday WHERE name LIKE '%Victoria Day%' AND date_holiday LIKE '2026%'" 2>/dev/null || true

# Verify it's gone
COUNT=$(oscar_query "SELECT COUNT(*) FROM public_holiday WHERE date_holiday='$HOLIDAY_DATE'" || echo "0")
if [ "$COUNT" -gt 0 ]; then
    echo "ERROR: Failed to clean up existing holiday record."
    # Try harder or fail
    exit 1
fi

echo "Clean state confirmed. Holiday record does not exist."

# Open Firefox on OSCAR login page
ensure_firefox_on_oscar

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup Complete ==="
echo "Task: Add Public Holiday"
echo "  Name: Victoria Day"
echo "  Date: May 18, 2026"
echo "  Credentials: oscardoc / oscar / PIN: 1117"