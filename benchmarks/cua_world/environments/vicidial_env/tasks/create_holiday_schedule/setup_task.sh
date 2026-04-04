#!/bin/bash
set -e

echo "=== Setting up create_holiday_schedule task ==="

source /workspace/scripts/task_utils.sh

# 1. Ensure Vicidial is running
vicidial_ensure_running

# 2. Prepare Database State (Clean Slate)
# Remove any existing holidays for 2025 to ensure the agent does the work
# and to prevent "Duplicate Entry" errors if the task is restarted.
echo "Clearing existing 2025 holidays..."
docker exec vicidial mysql -ucron -p1234 -D asterisk -e \
  "DELETE FROM vicidial_call_time_holidays WHERE holiday_date BETWEEN '2025-01-01' AND '2025-12-31';" \
  >/dev/null 2>&1 || true

# Record initial count (should be 0 for this date range)
INITIAL_COUNT=$(docker exec vicidial mysql -ucron -p1234 -D asterisk -N -e \
  "SELECT COUNT(*) FROM vicidial_call_time_holidays WHERE holiday_date BETWEEN '2025-01-01' AND '2025-12-31';" \
  2>/dev/null || echo "0")
echo "$INITIAL_COUNT" > /tmp/initial_holiday_count.txt

# Record start time for anti-gaming
date +%s > /tmp/task_start_time.txt

# 3. Launch Firefox and Login
# Vicidial uses HTTP Basic Auth which can block automation if not handled.
# We'll use the '6666' user which has permissions modified in the env setup.

ADMIN_URL="${VICIDIAL_ADMIN_URL:-http://localhost/vicidial/admin.php}"

# Close existing firefox instances
pkill -f firefox 2>/dev/null || true

echo "Launching Firefox..."
su - ga -c "DISPLAY=:1 firefox --new-window '${ADMIN_URL}' > /tmp/firefox_vicidial.log 2>&1 &"

# Wait for window
wait_for_window "firefox|mozilla|vicidial" 30 || true
focus_firefox
maximize_active_window

# Handle HTTP Basic Auth Login
echo "Attempting HTTP Basic Auth login..."
sleep 2
DISPLAY=:1 xdotool type --delay 50 "6666"
DISPLAY=:1 xdotool key Tab
DISPLAY=:1 xdotool type --delay 50 "andromeda"
DISPLAY=:1 xdotool key Return

# Wait for the admin page to load (look for "Administration" or similar in title/content)
sleep 5

# 4. Navigate to Admin Home (ensure we are not stuck on a previous page)
navigate_to_url "$ADMIN_URL"

# 5. Capture Initial State
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="