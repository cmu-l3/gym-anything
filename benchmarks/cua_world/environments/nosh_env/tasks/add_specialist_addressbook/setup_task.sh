#!/bin/bash
set -e
echo "=== Setting up task: add_specialist_addressbook ==="

# Record task start time
date +%s > /tmp/task_start_time.txt

# ==============================================================================
# Database Cleanup & Initial State
# ==============================================================================

# Remove any existing entry for Dr. Torres to ensure clean state
echo "Cleaning up any existing records for Dr. Torres..."
docker exec nosh-db mysql -uroot -prootpassword nosh -e \
  "DELETE FROM addressbook WHERE lastname='Torres' AND firstname='Rebecca';" 2>/dev/null || true

# Record initial addressbook count (for anti-gaming detection)
INITIAL_COUNT=$(docker exec nosh-db mysql -uroot -prootpassword nosh -N -e \
  "SELECT COUNT(*) FROM addressbook" 2>/dev/null || echo "0")
echo "$INITIAL_COUNT" > /tmp/initial_addressbook_count.txt
echo "Initial addressbook count: $INITIAL_COUNT"

# ==============================================================================
# Application Setup (Firefox & NOSH)
# ==============================================================================

# Ensure NOSH is responsive
echo "Checking NOSH availability..."
for i in {1..30}; do
    if curl -s -o /dev/null -w "%{http_code}" "http://localhost/login" | grep -q "200\|301\|302"; then
        echo "NOSH is responsive."
        break
    fi
    sleep 1
done

# Kill existing Firefox instances
pkill -9 -f firefox 2>/dev/null || true
sleep 2

# Launch Firefox
echo "Launching Firefox..."
# Check for snap vs native firefox
if snap list firefox &>/dev/null 2>&1; then
    FF_CMD="/snap/bin/firefox"
else
    FF_CMD="firefox"
fi

su - ga -c "DISPLAY=:1 $FF_CMD 'http://localhost/login' &"
sleep 5

# Wait for window
for i in {1..30}; do
    if DISPLAY=:1 wmctrl -l | grep -i -E "firefox|mozilla|nosh"; then
        echo "Firefox window detected."
        break
    fi
    sleep 1
done

# Maximize window
DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
sleep 1

# Focus window
DISPLAY=:1 wmctrl -a "Firefox" 2>/dev/null || true

# Take initial screenshot
DISPLAY=:1 scrot /tmp/task_initial_state.png 2>/dev/null || true

echo "=== Task setup complete ==="