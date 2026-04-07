#!/bin/bash
set -e
echo "=== Setting up compose_patient_letter task ==="

# 1. Record task start time for anti-gaming verification
date +%s > /tmp/task_start_time.txt

# 2. Prepare Database State
# We use a fixed PID (9999) to ensure reliable verification and avoid conflicts with auto-generated data
echo "Preparing patient data..."
docker exec nosh-db mysql -uroot -prootpassword nosh -e "
-- Create or update the target patient
INSERT INTO demographics (pid, firstname, lastname, DOB, sex, address, city, state, zip, phone_home, active, practice_id)
VALUES (9999, 'Walter', 'Bishop', '1948-01-20', 'Male', '17 Harvard St', 'Boston', 'MA', '02138', '617-555-1985', 1, 1)
ON DUPLICATE KEY UPDATE 
    firstname='Walter', lastname='Bishop', active=1;

-- Link patient to practice (required for search visibility)
INSERT IGNORE INTO demographics_relate (pid, id, practice_id) VALUES (9999, 2, 1);

-- Clear any existing documents for this patient to ensure clean state
DELETE FROM documents WHERE pid=9999;
" 2>/dev/null

# 3. Record initial state (should be 0 documents)
INITIAL_COUNT=$(docker exec nosh-db mysql -uroot -prootpassword nosh -N -e "SELECT COUNT(*) FROM documents WHERE pid=9999;" 2>/dev/null || echo "0")
echo "$INITIAL_COUNT" > /tmp/initial_doc_count.txt

# 4. Launch Application (Firefox)
echo "Launching Firefox..."
# Kill any existing instances
pkill -9 -f firefox 2>/dev/null || true
sleep 2

# Set up Firefox profile paths
FF_SNAP="/home/ga/snap/firefox/common/.mozilla/firefox"
FF_NATIVE="/home/ga/.mozilla/firefox"

# Clean locks
for profile_dir in "$FF_SNAP" "$FF_NATIVE"; do
    if [ -d "$profile_dir" ]; then
        find "$profile_dir" -name ".parentlock" -delete 2>/dev/null || true
        find "$profile_dir" -name "lock" -delete 2>/dev/null || true
    fi
done

# Launch Firefox
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

# 5. Wait for window and maximize
echo "Waiting for Firefox window..."
for i in {1..30}; do
    WID=$(DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority wmctrl -l 2>/dev/null | grep -i "firefox\|mozilla\|nosh" | head -1 | awk '{print $1}')
    if [ -n "$WID" ]; then
        echo "Window found: $WID"
        DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority wmctrl -ia "$WID" 2>/dev/null || true
        sleep 1
        DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
        break
    fi
    sleep 1
done

# 6. Capture initial screenshot
sleep 2
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Task setup complete ==="