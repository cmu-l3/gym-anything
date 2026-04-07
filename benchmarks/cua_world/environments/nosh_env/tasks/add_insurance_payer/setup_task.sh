#!/bin/bash
# Setup task: add_insurance_payer
# Start state: NOSH login page
echo "=== Setting up add_insurance_payer task ==="

# 1. Clean up: Remove any existing entry for Aetna Better Health to ensure a clean start
echo "Cleaning database..."
docker exec nosh-db mysql -uroot -prootpassword nosh -e \
  "DELETE FROM addressbook WHERE displayname LIKE '%Aetna Better Health%';" 2>/dev/null || true

# 2. Record initial state for anti-gaming verification
echo "Recording initial state..."
INITIAL_COUNT=$(docker exec nosh-db mysql -uroot -prootpassword nosh -N -e "SELECT COUNT(*) FROM addressbook" 2>/dev/null || echo "0")
echo "$INITIAL_COUNT" > /tmp/initial_count.txt
date +%s > /tmp/task_start_time.txt

# 3. Setup Browser (Firefox)
echo "Setting up browser..."
# Kill existing Firefox
pkill -9 -f firefox 2>/dev/null || true
sleep 3

# Remove Firefox lock files (common issue in persistent environments)
FF_SNAP="/home/ga/snap/firefox/common/.mozilla/firefox"
FF_NATIVE="/home/ga/.mozilla/firefox"
for profile_dir in "$FF_SNAP" "$FF_NATIVE"; do
    if [ -d "$profile_dir" ]; then
        find "$profile_dir" -name ".parentlock" -delete 2>/dev/null || true
        find "$profile_dir" -name "lock" -delete 2>/dev/null || true
    fi
done

# Fix permissions
chown -R ga:ga /home/ga/snap 2>/dev/null || true
chown -R ga:ga /home/ga/.mozilla 2>/dev/null || true

# Launch Firefox pointing to NOSH login
NOSH_URL="http://localhost/login"
if snap list firefox &>/dev/null 2>&1; then
    FF_PROFILE="$FF_SNAP/nosh.profile"
    mkdir -p "$FF_PROFILE"
    su - ga -c "DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority setsid /snap/bin/firefox --new-instance -profile '$FF_PROFILE' '$NOSH_URL' > /tmp/firefox_task.log 2>&1 &"
else
    FF_PROFILE="$FF_NATIVE/default-release"
    mkdir -p "$FF_PROFILE"
    su - ga -c "DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority setsid firefox -profile '$FF_PROFILE' '$NOSH_URL' > /tmp/firefox_task.log 2>&1 &"
fi

sleep 5

# 4. Window Management (Maximize and Focus)
echo "Configuring window..."
for i in $(seq 1 20); do
    WID=$(DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority wmctrl -l 2>/dev/null | grep -i "firefox\|mozilla\|nosh" | head -1 | awk '{print $1}')
    if [ -n "$WID" ]; then
        # Focus
        DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority wmctrl -ia "$WID" 2>/dev/null || true
        # Maximize
        DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
        break
    fi
    sleep 1
done

# 5. Capture Initial Screenshot
echo "Capturing initial screenshot..."
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Task setup complete: add_insurance_payer ==="