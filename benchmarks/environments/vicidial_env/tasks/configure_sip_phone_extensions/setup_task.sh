#!/bin/bash
set -e
echo "=== Setting up configure_sip_phone_extensions task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Ensure Vicidial is running
vicidial_ensure_running

# Wait for MySQL to be accessible
echo "Waiting for Vicidial MySQL..."
for i in $(seq 1 60); do
    if docker exec vicidial mysql -ucron -p1234 -D asterisk -e "SELECT 1;" >/dev/null 2>&1; then
        echo "MySQL is ready"
        break
    fi
    sleep 2
done

# Clean up any pre-existing phone entries for 8501/8502 to ensure clean state
echo "Cleaning up any pre-existing phone entries..."
docker exec vicidial mysql -ucron -p1234 -D asterisk -e \
    "DELETE FROM phones WHERE extension IN ('8501','8502');" 2>/dev/null || true

# Record initial phone count
INITIAL_PHONE_COUNT=$(docker exec vicidial mysql -ucron -p1234 -D asterisk -N -e \
    "SELECT COUNT(*) FROM phones;" 2>/dev/null || echo "0")
echo "$INITIAL_PHONE_COUNT" > /tmp/initial_phone_count.txt
echo "Initial phone count: $INITIAL_PHONE_COUNT"

# Ensure Firefox is running and showing admin panel
pkill -f firefox 2>/dev/null || true
sleep 2

# Launch Firefox to the Admin panel
su - ga -c "DISPLAY=:1 firefox 'http://localhost/vicidial/admin.php' > /tmp/firefox_vicidial.log 2>&1 &"

# Wait for Firefox window
for i in $(seq 1 30); do
    WID=$(DISPLAY=:1 wmctrl -l 2>/dev/null | grep -i 'firefox\|mozilla\|vicidial' | head -1 | awk '{print $1}')
    [ -n "$WID" ] && break
    sleep 1
done

sleep 5

if [ -n "$WID" ]; then
    DISPLAY=:1 wmctrl -ia "$WID" 2>/dev/null || true
    DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
fi

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="