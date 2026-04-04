#!/bin/bash
set -e

echo "=== Setting up Configure System Settings Task ==="

source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Ensure Vicidial is running
vicidial_ensure_running

# Reset System Settings to known default state (all target fields disabled/0)
# This ensures the task is actually performed and not just passing by chance
echo "Resetting System Settings to default state..."
docker exec vicidial mysql -ucron -p1234 -D asterisk -e "UPDATE system_settings SET use_non_latin='0', custom_fields_enabled='0', allow_chats='0', callback_limit='0', enable_queuemetrics_logging='0', allow_emails='0' LIMIT 1;"

# Verify reset
echo "Verifying initial state..."
docker exec vicidial mysql -ucron -p1234 -D asterisk -e "SELECT use_non_latin, custom_fields_enabled, allow_chats, callback_limit, enable_queuemetrics_logging, allow_emails FROM system_settings LIMIT 1\G" > /tmp/initial_db_state.txt
cat /tmp/initial_db_state.txt

# Capture initial state in JSON for export/verifier to use as baseline
cat > /tmp/initial_state.json << EOF
{
  "use_non_latin": "0",
  "custom_fields_enabled": "0",
  "allow_chats": "0",
  "callback_limit": "0",
  "enable_queuemetrics_logging": "0",
  "allow_emails": "0",
  "timestamp": "$(date +%s)"
}
EOF

# Setup Firefox
echo "Launching Firefox to Admin Interface..."
# Close any existing firefox
pkill -f firefox 2>/dev/null || true

# Start Firefox at the Admin main page (not directly at settings, to test navigation)
START_URL="${VICIDIAL_ADMIN_URL}?ADD=3" # ADD=3 is Reports, generic admin page
su - ga -c "DISPLAY=:1 firefox '${START_URL}' > /tmp/firefox.log 2>&1 &"

# Wait for window
wait_for_window "firefox\|mozilla" 30
focus_firefox
maximize_active_window

# Handle HTTP Basic Auth if needed (using xdotool blindly as a fallback)
sleep 2
DISPLAY=:1 xdotool type "6666"
DISPLAY=:1 xdotool key Tab
DISPLAY=:1 xdotool type "andromeda"
DISPLAY=:1 xdotool key Return
sleep 3

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task Setup Complete ==="