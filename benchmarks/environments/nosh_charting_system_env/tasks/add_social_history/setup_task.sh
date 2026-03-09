#!/bin/bash
# Setup task: add_social_history
# Target patient: Conchita Hernandes (pid=1)
# Start state: NOSH login page
echo "=== Setting up add_social_history task ==="

# Remove any existing social history entries for this patient
docker exec nosh-db mysql -uroot -prootpassword nosh -e \
  "DELETE FROM other_history WHERE pid=1 AND eid=0;" 2>/dev/null || true

# Kill existing Firefox
pkill -9 -f firefox 2>/dev/null || true
sleep 3

FF_SNAP="/home/ga/snap/firefox/common/.mozilla/firefox"
FF_NATIVE="/home/ga/.mozilla/firefox"
for profile_dir in "$FF_SNAP" "$FF_NATIVE"; do
    if [ -d "$profile_dir" ]; then
        find "$profile_dir" -name ".parentlock" -delete 2>/dev/null || true
        find "$profile_dir" -name "lock" -delete 2>/dev/null || true
    fi
done

chown -R ga:ga /home/ga/snap 2>/dev/null || true
chown -R ga:ga /home/ga/.mozilla 2>/dev/null || true

if snap list firefox &>/dev/null 2>&1; then
    FF_PROFILE="$FF_SNAP/nosh.profile"
    mkdir -p "$FF_PROFILE"
    su - ga -c "DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority setsid /snap/bin/firefox --new-instance -profile '$FF_PROFILE' 'http://localhost/login' > /tmp/firefox_task.log 2>&1 &"
else
    FF_PROFILE="$FF_NATIVE/default-release"
    mkdir -p "$FF_PROFILE"
    su - ga -c "DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority setsid firefox -profile '$FF_PROFILE' 'http://localhost/login' > /tmp/firefox_task.log 2>&1 &"
fi

sleep 5

for i in $(seq 1 20); do
    WID=$(DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority wmctrl -l 2>/dev/null | grep -i "firefox\|mozilla\|nosh" | head -1 | awk '{print $1}')
    if [ -n "$WID" ]; then
        DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority wmctrl -ia "$WID" 2>/dev/null || true
        DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
        break
    fi
    sleep 1
done

echo "=== Task setup complete: add_social_history ==="
echo "NOSH login page is open. Agent should log in as demo_provider and add social history for Conchita Hernandes."
