#!/bin/bash
# Setup task: send_message
# Provider sends internal message to admin
# Start state: NOSH login page
echo "=== Setting up send_message task ==="

# Clean up any previous test messages with this subject
docker exec nosh-db mysql -uroot -prootpassword nosh -e \
  "DELETE FROM messaging WHERE subject LIKE '%Lab Result Follow-up%' AND message_from=2;" 2>/dev/null || true

# Ensure second provider user (Dr. Emily Brooks, id=3) exists as message recipient
# NOTE: NOSH's array_users_all() excludes group_id=1 (admin) from messaging dropdown,
# so a second group_id=2 provider is required as the recipient.
PROV2_HASH=$(docker exec nosh-app php -r "echo password_hash('Provider1234!', PASSWORD_BCRYPT, ['cost' => 10]);" 2>/dev/null)
if [ -n "$PROV2_HASH" ]; then
    docker exec nosh-db mysql -uroot -prootpassword nosh -e \
      "INSERT IGNORE INTO users (id, username, email, displayname, firstname, lastname, password, group_id, active, practice_id) VALUES (3, 'dr_brooks', 'ebrooks@hillsidefm.local', 'Dr. Emily Brooks', 'Emily', 'Brooks', '${PROV2_HASH}', 2, 1, 1);" 2>/dev/null || true
fi

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

echo "=== Task setup complete: send_message ==="
echo "NOSH login page is open. Agent should log in as demo_provider and send internal message to admin."
