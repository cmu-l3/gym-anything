#!/bin/bash
set -e
echo "=== Setting up Configure Campaign Hotkeys Task ==="

source /workspace/scripts/task_utils.sh

# 1. Record task start time
date +%s > /tmp/task_start_time.txt

# 2. Ensure Vicidial is running
vicidial_ensure_running

# 3. Clean up environment (Anti-gaming: ensure target campaign does not exist)
echo "Cleaning up any existing 'RAPID' campaign..."
wait_for_mysql() {
  for i in $(seq 1 30); do
    if docker exec vicidial mysql -ucron -p1234 -D asterisk -e "SELECT 1;" >/dev/null 2>&1; then
      return 0
    fi
    sleep 1
  done
  return 1
}

wait_for_mysql

# Delete campaign and associated hotkeys if they exist
docker exec vicidial mysql -ucron -p1234 -D asterisk -e "DELETE FROM vicidial_campaigns WHERE campaign_id='RAPID';" 2>/dev/null || true
docker exec vicidial mysql -ucron -p1234 -D asterisk -e "DELETE FROM vicidial_campaign_hotkeys WHERE campaign_id='RAPID';" 2>/dev/null || true

# 4. Prepare Firefox
# Start Firefox if not running, or focus it
if ! pgrep -f firefox > /dev/null; then
    echo "Starting Firefox..."
    su - ga -c "DISPLAY=:1 firefox '${VICIDIAL_ADMIN_URL}' > /tmp/firefox_task.log 2>&1 &"
    
    # Wait for window
    wait_for_window "firefox\|mozilla\|vicidial" 60
else
    # Navigate to Admin URL if already open
    focus_firefox
    navigate_to_url "${VICIDIAL_ADMIN_URL}"
fi

maximize_active_window

# 5. Handle Login (if redirected to login screen)
# Note: The environment usually has auto-login or basic auth handled, but we ensure we are at the menu
sleep 3
# If we see a login form (unlikely with basic auth pre-fill, but good practice)
# We assume the agent starts logged in or at the prompt. 
# The instruction implies they are logged in as admin.

# 6. Initial Screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup complete ==="