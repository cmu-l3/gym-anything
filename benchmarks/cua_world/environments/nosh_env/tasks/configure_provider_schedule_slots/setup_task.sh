#!/bin/bash
# Setup script for Configure Provider Schedule Slots task
set -e

echo "=== Setting up Configure Provider Schedule Slots Task ==="

# 1. Define constants
DB_USER="root"
DB_PASS="rootpassword"
DB_NAME="nosh"
TARGET_USER="demo_provider"
INITIAL_INCREMENT=20

# 2. Record task start time (anti-gaming)
date +%s > /tmp/task_start_time.txt

# 3. Ensure the provider exists and set to KNOWN INITIAL STATE (20 min slots)
# We update the providers table where the linked user_id matches the demo_provider
echo "Resetting provider schedule increment to ${INITIAL_INCREMENT}..."
docker exec nosh-db mysql -u$DB_USER -p$DB_PASS $DB_NAME -e \
    "UPDATE providers SET schedule_increment=${INITIAL_INCREMENT} WHERE id=(SELECT id FROM users WHERE username='${TARGET_USER}');"

# 4. Verify initial state in DB
CURRENT_VAL=$(docker exec nosh-db mysql -u$DB_USER -p$DB_PASS $DB_NAME -N -e \
    "SELECT schedule_increment FROM providers WHERE id=(SELECT id FROM users WHERE username='${TARGET_USER}');")

echo "Initial schedule increment in DB: $CURRENT_VAL"
echo "$CURRENT_VAL" > /tmp/initial_increment.txt

# 5. Prepare Firefox (Clean state)
echo "Preparing Firefox..."
pkill -9 -f firefox 2>/dev/null || true
sleep 2

# Clear locks
find /home/ga/.mozilla/firefox -name "*.lock" -delete 2>/dev/null || true
find /home/ga/snap/firefox/common/.mozilla/firefox -name "*.lock" -delete 2>/dev/null || true

# Launch Firefox to Login Page
NOSH_URL="http://localhost/login"
if snap list firefox &>/dev/null 2>&1; then
    su - ga -c "DISPLAY=:1 /snap/bin/firefox --new-instance '$NOSH_URL' > /dev/null 2>&1 &"
else
    su - ga -c "DISPLAY=:1 firefox '$NOSH_URL' > /dev/null 2>&1 &"
fi

# 6. Wait for window and maximize
echo "Waiting for Firefox window..."
for i in {1..30}; do
    WID=$(DISPLAY=:1 wmctrl -l | grep -i "Mozilla Firefox" | awk '{print $1}' | head -1)
    if [ -n "$WID" ]; then
        echo "Firefox window found: $WID"
        # Maximize
        DISPLAY=:1 wmctrl -ir "$WID" -b add,maximized_vert,maximized_horz
        # Focus
        DISPLAY=:1 wmctrl -ia "$WID"
        break
    fi
    sleep 1
done

# 7. Take initial screenshot
sleep 3
echo "Capturing initial state..."
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup Complete ==="