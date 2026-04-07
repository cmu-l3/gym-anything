#!/bin/bash
# Setup task: multi_specialist_referral_workflow
# Target patient: Malka Hartmann (pid=12, DOB: 1994-11-26)
# Also requires dr_brooks user (id=3) for messaging
# Start state: NOSH login page
echo "=== Setting up multi_specialist_referral_workflow task ==="

# Clean prior task artifacts for this patient
docker exec nosh-db mysql -uroot -prootpassword nosh -e \
  "DELETE FROM encounters WHERE pid=12;" 2>/dev/null || true
docker exec nosh-db mysql -uroot -prootpassword nosh -e \
  "DELETE FROM orders WHERE pid=12;" 2>/dev/null || true
docker exec nosh-db mysql -uroot -prootpassword nosh -e \
  "DELETE FROM messaging WHERE message_from=2 AND subject LIKE '%Hartmann%';" 2>/dev/null || true
docker exec nosh-db mysql -uroot -prootpassword nosh -e \
  "DELETE FROM messaging WHERE message_from=2 AND subject LIKE '%Cardiology%';" 2>/dev/null || true

# Ensure second provider user (Dr. Emily Brooks, id=3) exists as message recipient
# NOTE: NOSH's array_users_all() excludes group_id=1 (admin) from messaging dropdown,
# so a second group_id=2 provider is required as the recipient.
PROV2_HASH=$(docker exec nosh-app php -r "echo password_hash('Provider1234!', PASSWORD_BCRYPT, ['cost' => 10]);" 2>/dev/null)
if [ -n "$PROV2_HASH" ]; then
    docker exec nosh-db mysql -uroot -prootpassword nosh -e \
      "INSERT IGNORE INTO users (id, username, email, displayname, firstname, lastname, password, group_id, active, practice_id) VALUES (3, 'dr_brooks', 'ebrooks@hillsidefm.local', 'Dr. Emily Brooks', 'Emily', 'Brooks', '${PROV2_HASH}', 2, 1, 1);" 2>/dev/null || true
fi

# Record baseline state for anti-gaming verification
echo "$(date +%s)" > /tmp/msrw_start_time.txt
INIT_ENC=$(docker exec nosh-db mysql -uroot -prootpassword nosh -N -e \
  "SELECT COUNT(*) FROM encounters WHERE pid=12;" 2>/dev/null || echo "0")
INIT_ORD=$(docker exec nosh-db mysql -uroot -prootpassword nosh -N -e \
  "SELECT COUNT(*) FROM orders WHERE pid=12;" 2>/dev/null || echo "0")
echo "${INIT_ENC:-0}" > /tmp/msrw_init_enc.txt
echo "${INIT_ORD:-0}" > /tmp/msrw_init_ord.txt

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

echo "=== Task setup complete: multi_specialist_referral_workflow ==="
echo "Malka Hartmann (pid=12) chart is clean. Dr. Brooks (id=3) verified as messaging target."
echo "Agent must: create encounter, order TSH+CBC labs, place Endo+Cardiology referrals, send message to Dr. Brooks."
