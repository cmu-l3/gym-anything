#!/bin/bash
set -e
echo "=== Setting up configure_inbound_did_routing task ==="

# Source shared utilities if available
if [ -f /workspace/scripts/task_utils.sh ]; then
    source /workspace/scripts/task_utils.sh
fi

# Record task start time
date +%s > /tmp/task_start_time.txt

# Ensure Vicidial container is running
if [ -x /usr/local/bin/vicidial-ensure-running ]; then
    /usr/local/bin/vicidial-ensure-running
fi

# Wait for MySQL to be responsive
echo "Waiting for Vicidial MySQL..."
for i in $(seq 1 60); do
    if docker exec vicidial mysql -ucron -p1234 -D asterisk -e "SELECT 1;" >/dev/null 2>&1; then
        echo "MySQL is ready"
        break
    fi
    sleep 2
    if [ "$i" -eq 60 ]; then
        echo "ERROR: MySQL not ready after 120s"
        exit 1
    fi
done

# Clean up any pre-existing test data to ensure clean state
echo "Cleaning any pre-existing test data..."
docker exec vicidial mysql -ucron -p1234 -D asterisk -e \
    "DELETE FROM vicidial_inbound_groups WHERE group_id = 'GREENFIELD_SUP';" 2>/dev/null || true
docker exec vicidial mysql -ucron -p1234 -D asterisk -e \
    "DELETE FROM vicidial_inbound_dids WHERE did_pattern = '8005559247';" 2>/dev/null || true

# Record initial counts for anti-gaming
INITIAL_IG_COUNT=$(docker exec vicidial mysql -ucron -p1234 -D asterisk -N -e \
    "SELECT COUNT(*) FROM vicidial_inbound_groups;" 2>/dev/null || echo "0")
echo "$INITIAL_IG_COUNT" > /tmp/initial_ig_count.txt

INITIAL_DID_COUNT=$(docker exec vicidial mysql -ucron -p1234 -D asterisk -N -e \
    "SELECT COUNT(*) FROM vicidial_inbound_dids;" 2>/dev/null || echo "0")
echo "$INITIAL_DID_COUNT" > /tmp/initial_did_count.txt

echo "Initial In-Group count: $INITIAL_IG_COUNT"
echo "Initial DID count: $INITIAL_DID_COUNT"

# Ensure Firefox is running and focused on admin panel
pkill -f firefox 2>/dev/null || true
sleep 2

ADMIN_URL="http://localhost/vicidial/admin.php"
echo "Launching Firefox..."
su - ga -c "DISPLAY=:1 firefox '$ADMIN_URL' > /tmp/firefox_vicidial.log 2>&1 &"

# Wait for Firefox window
echo "Waiting for Firefox..."
for i in $(seq 1 30); do
    if DISPLAY=:1 wmctrl -l 2>/dev/null | grep -i 'firefox\|mozilla\|vicidial'; then
        echo "Firefox window found"
        break
    fi
    sleep 1
done

sleep 5

# Maximize and focus
DISPLAY=:1 wmctrl -a "Firefox" 2>/dev/null || DISPLAY=:1 wmctrl -a "Mozilla" 2>/dev/null || true
DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true

# Login if needed (Basic Auth handling via xdotool)
# Note: In some environments, the URL includes user/pass or pre-auth is done.
# If a prompt appears, we attempt to handle it.
sleep 2
if DISPLAY=:1 xwininfo -root -tree | grep -i "Authentication Required"; then
    echo "Handling Basic Auth prompt..."
    DISPLAY=:1 xdotool type --delay 50 "6666"
    DISPLAY=:1 xdotool key Tab
    DISPLAY=:1 xdotool type --delay 50 "andromeda"
    DISPLAY=:1 xdotool key Return
fi

# Take initial state screenshot
echo "Capturing initial state..."
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || \
    DISPLAY=:1 import -window root /tmp/task_initial.png 2>/dev/null || true

echo "=== Task setup complete ==="