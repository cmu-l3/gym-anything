#!/bin/bash
set -e
echo "=== Setting up task: create_call_time_restriction ==="

# Record task start time for anti-gaming detection
date +%s > /tmp/task_start_time.txt

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Step 1: Ensure Vicidial is running
echo "Ensuring Vicidial is running..."
vicidial_ensure_running

# Step 2: Ensure admin user has full permissions (including call time management)
echo "Ensuring admin permissions..."
for i in $(seq 1 30); do
  if docker exec vicidial mysql -ucron -p1234 -D asterisk -e "SELECT 1;" >/dev/null 2>&1; then
    echo "MySQL is ready"
    break
  fi
  sleep 2
done

# Set permissions for user 6666 to ensure they can modify call times
docker exec vicidial mysql -ucron -p1234 -D asterisk -e \
  "UPDATE vicidial_users SET user_level=9, modify_campaigns='1', ast_admin_access='1', modify_lists='1', modify_leads='1', modify_call_times='1', calltime_override='1' WHERE user='6666';" \
  >/dev/null 2>&1 || true

# Step 3: Clean state - remove any existing EASTERN_TCPA call time from a previous run
echo "Cleaning previous task state..."
docker exec vicidial mysql -ucron -p1234 -D asterisk -e \
  "DELETE FROM vicidial_call_times WHERE call_time_id='EASTERN_TCPA';" \
  >/dev/null 2>&1 || true

# Record that the call time does NOT exist before the task begins
EXISTING=$(docker exec vicidial mysql -ucron -p1234 -D asterisk -N -e \
  "SELECT COUNT(*) FROM vicidial_call_times WHERE call_time_id='EASTERN_TCPA';" 2>/dev/null || echo "0")
echo "$EXISTING" > /tmp/initial_call_time_count.txt
echo "Initial EASTERN_TCPA count: $EXISTING"

# Step 4: Kill any existing Firefox and relaunch pointed at admin page
echo "Launching Firefox with Vicidial Admin..."
pkill -f firefox 2>/dev/null || true
sleep 2

# Using the generic admin URL; agent must log in
ADMIN_URL="${VICIDIAL_ADMIN_URL:-http://localhost/vicidial/admin.php}"
su - ga -c "DISPLAY=:1 firefox '$ADMIN_URL' > /tmp/firefox_vicidial.log 2>&1 &"

# Step 5: Wait for Firefox window
echo "Waiting for Firefox window..."
for i in $(seq 1 30); do
  WID=$(DISPLAY=:1 wmctrl -l 2>/dev/null | grep -iE 'firefox|mozilla|vicidial' | head -1 | awk '{print $1}')
  if [ -n "$WID" ]; then
    echo "Firefox window found: $WID"
    break
  fi
  sleep 1
done

# Maximize and focus
if [ -n "$WID" ]; then
  DISPLAY=:1 wmctrl -ia "$WID" 2>/dev/null || true
  DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
fi

# Wait for page to finish loading
sleep 5

# Step 6: Take initial screenshot
echo "Taking initial screenshot..."
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="