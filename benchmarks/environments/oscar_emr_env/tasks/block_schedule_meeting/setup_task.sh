#!/bin/bash
set -e
echo "=== Setting up Task: Block Schedule Meeting ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time (for anti-gaming)
date +%s > /tmp/task_start_time.txt

# Ensure OSCAR is reachable
wait_for_oscar_http 300

# ============================================================
# 1. Clear any existing appointments for Dr. Chen on target date
#    This ensures the agent starts with a clean slate for that day.
# ============================================================
TARGET_DATE="2026-03-20"
PROVIDER_NO="999998" # oscardoc / Dr. Chen

echo "Clearing schedule for $TARGET_DATE..."
# We delete from appointment table. 
# Note: In some OSCAR versions, we might need to be careful about linked tables, 
# but for a pure block/meeting entry, deleting from appointment is usually sufficient for a reset.
oscar_query "DELETE FROM appointment WHERE provider_no='$PROVIDER_NO' AND appointment_date='$TARGET_DATE'"

# Verify it's empty
COUNT=$(oscar_query "SELECT COUNT(*) FROM appointment WHERE provider_no='$PROVIDER_NO' AND appointment_date='$TARGET_DATE'")
echo "Appointments on target date after cleanup: $COUNT"

# ============================================================
# 2. Start Firefox on OSCAR login
# ============================================================
ensure_firefox_on_oscar

# Take initial screenshot
take_screenshot /tmp/task_initial_state.png

echo "=== Task setup complete ==="