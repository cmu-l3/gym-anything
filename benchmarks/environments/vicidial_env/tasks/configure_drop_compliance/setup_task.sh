#!/bin/bash
set -e
echo "=== Setting up Configure Drop Compliance Task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Ensure Vicidial is running
vicidial_ensure_running

# Wait for MySQL to be ready
echo "Waiting for MySQL..."
for i in $(seq 1 30); do
  if docker exec vicidial mysql -ucron -p1234 -D asterisk -e "SELECT 1;" >/dev/null 2>&1; then
    echo "MySQL is ready"
    break
  fi
  sleep 2
done

# Reset compliance fields to non-compliant defaults to ensure agent must do work
echo "Resetting campaign TESTCAMP to non-compliant state..."
docker exec vicidial mysql -ucron -p1234 -D asterisk -e "
  UPDATE vicidial_campaigns SET
    drop_call_seconds = 0,
    safe_harbor_exten = '',
    safe_harbor_message = '',
    drop_lockout_time = 0,
    safe_harbor_audio_field = 'NONE'
  WHERE campaign_id = 'TESTCAMP';
" 2>/dev/null || echo "WARNING: Could not reset compliance fields"

# Record initial state for anti-gaming verification
INITIAL_STATE=$(docker exec vicidial mysql -ucron -p1234 -D asterisk -N -e \
  "SELECT drop_call_seconds, safe_harbor_exten, safe_harbor_message, drop_lockout_time, safe_harbor_audio_field FROM vicidial_campaigns WHERE campaign_id='TESTCAMP';" 2>/dev/null | tr '\t' '|' || echo "QUERY_FAILED")
echo "$INITIAL_STATE" > /tmp/initial_state_check.txt

# Start Firefox and navigate to Admin
# Use admin credentials: 6666 / andromeda
VICIDIAL_URL="http://localhost/vicidial/admin.php"

if ! pgrep -f firefox > /dev/null; then
    echo "Starting Firefox..."
    su - ga -c "DISPLAY=:1 firefox '$VICIDIAL_URL' > /tmp/firefox_task.log 2>&1 &"
    sleep 5
fi

# Wait for window and maximize
wait_for_window "firefox\|mozilla\|vicidial" 30
WID=$(DISPLAY=:1 wmctrl -l | grep -i "firefox\|mozilla\|vicidial" | head -1 | awk '{print $1}')
if [ -n "$WID" ]; then
    DISPLAY=:1 wmctrl -ia "$WID"
    maximize_active_window
fi

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup Complete ==="