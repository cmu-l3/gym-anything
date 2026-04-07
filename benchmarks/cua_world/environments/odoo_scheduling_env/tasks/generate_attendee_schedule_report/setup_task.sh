#!/bin/bash
echo "=== Setting up generate_attendee_schedule_report task ==="

source /workspace/scripts/task_utils.sh

# 1. Record task start time (anti-gaming)
date +%s > /tmp/task_start_time.txt

# 2. Clean up previous artifacts
OUTPUT_FILE="/home/ga/Documents/grace_patel_schedule.txt"
rm -f "$OUTPUT_FILE" 2>/dev/null || true
mkdir -p /home/ga/Documents

# 3. Ensure Odoo is running and accessible
# (Hooks handle basic setup, but we verify here)
wait_for_odoo_service 60

# 4. Launch Firefox directly to the Calendar view
# The agent needs to start here to perform the search
echo "Launching Firefox to Calendar view..."
ensure_firefox "http://localhost:8069/web#action=calendar.action_calendar_event"

# 5. Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup complete ==="
echo "Target: Grace Patel"
echo "Output: $OUTPUT_FILE"