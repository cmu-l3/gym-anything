#!/bin/bash
set -e
echo "=== Setting up task: add_lab_order ==="

# Record task start time
date +%s > /tmp/task_start_time.txt

# ============================================================
# Ensure NOSH containers are running
# ============================================================
cd /home/ga/nosh
if ! docker compose ps | grep -q "nosh-app.*running"; then
    echo "Starting NOSH containers..."
    docker compose up -d
    sleep 30
fi

# Wait for NOSH to be ready
echo "Waiting for NOSH to be ready..."
for i in $(seq 1 60); do
    HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" "http://localhost/login" 2>/dev/null)
    if [ "$HTTP_CODE" = "200" ] || [ "$HTTP_CODE" = "302" ]; then
        echo "NOSH is ready (HTTP $HTTP_CODE)"
        break
    fi
    sleep 3
done

# ============================================================
# Ensure patient Margaret Thompson exists (pid=900)
# ============================================================
echo "Ensuring patient Margaret Thompson exists..."

# Check if patient already exists
EXISTING=$(docker exec nosh-db mysql -uroot -prootpassword nosh -N -e \
    "SELECT COUNT(*) FROM demographics WHERE pid=900;" 2>/dev/null || echo "0")

if [ "$EXISTING" = "0" ] || [ -z "$EXISTING" ]; then
    echo "Creating patient Margaret Thompson (pid=900)..."
    
    # Insert patient directly into DB to ensure consistent starting state
    docker exec -i nosh-db mysql -uroot -prootpassword nosh <<'SQLEOF'
INSERT INTO `demographics` (`pid`, `lastname`, `firstname`, `DOB`, `sex`, `address`, `city`, `state`, `zip`, `phone_home`, `active`, `date`, `email`)
VALUES (900, 'Thompson', 'Margaret', '1958-04-22', 'Female', '45 Elm Street', 'Springfield', 'MA', '01103', '413-555-8822', 1, NOW(), 'mthompson@email.com')
ON DUPLICATE KEY UPDATE `lastname`='Thompson', `firstname`='Margaret';

INSERT IGNORE INTO `demographics_relate` (`pid`, `id`, `practice_id`)
VALUES (900, 2, 1);
SQLEOF
    echo "Patient created."
else
    echo "Patient Margaret Thompson already exists."
fi

# ============================================================
# Record initial order count for anti-gaming
# ============================================================
INITIAL_ORDERS=$(docker exec nosh-db mysql -uroot -prootpassword nosh -N -e \
    "SELECT COUNT(*) FROM orders WHERE pid=900;" 2>/dev/null || echo "0")
echo "$INITIAL_ORDERS" > /tmp/initial_order_count.txt
echo "Initial orders for Margaret Thompson: $INITIAL_ORDERS"

# ============================================================
# Kill any existing Firefox instances
# ============================================================
pkill -f firefox 2>/dev/null || true
sleep 2

# ============================================================
# Open Firefox to NOSH login page
# ============================================================
echo "Opening Firefox to NOSH login page..."

# Handle Snap vs Native Firefox paths for profiles
FF_SNAP="/home/ga/snap/firefox/common/.mozilla/firefox"
FF_NATIVE="/home/ga/.mozilla/firefox"
for profile_dir in "$FF_SNAP" "$FF_NATIVE"; do
    if [ -d "$profile_dir" ]; then
        find "$profile_dir" -name ".parentlock" -delete 2>/dev/null || true
        find "$profile_dir" -name "lock" -delete 2>/dev/null || true
    fi
done

if snap list firefox &>/dev/null 2>&1; then
    FF_PROFILE="$FF_SNAP/nosh.profile"
    mkdir -p "$FF_PROFILE"
    su - ga -c "DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority setsid /snap/bin/firefox --new-instance -profile '$FF_PROFILE' 'http://localhost/login' > /tmp/firefox_task.log 2>&1 &"
else
    FF_PROFILE="$FF_NATIVE/default-release"
    mkdir -p "$FF_PROFILE"
    su - ga -c "DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority setsid firefox -profile '$FF_PROFILE' 'http://localhost/login' > /tmp/firefox_task.log 2>&1 &"
fi

sleep 8

# Wait for Firefox window
for i in $(seq 1 20); do
    WID=$(DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority wmctrl -l 2>/dev/null | grep -i "firefox\|mozilla\|nosh" | head -1 | awk '{print $1}')
    if [ -n "$WID" ]; then
        echo "Firefox window detected: $WID"
        # Maximize Firefox
        DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority wmctrl -ia "$WID" 2>/dev/null || true
        DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
        break
    fi
    sleep 2
done

# Take initial screenshot
DISPLAY=:1 scrot /tmp/task_initial_state.png 2>/dev/null || true

echo "=== Task setup complete ==="