#!/bin/bash
# Setup task: discontinue_medication
# Target patient: Denny Lubowitz (pid=8, female)
# Pre-adds an active Metformin prescription that the agent must discontinue
# Start state: NOSH login page
echo "=== Setting up discontinue_medication task ==="

# Remove any existing Metformin entries for this patient to start clean
docker exec nosh-db mysql -uroot -prootpassword nosh -e \
  "DELETE FROM rx_list WHERE pid=8 AND upper(rxl_medication) LIKE '%METFORMIN%';" 2>/dev/null || true

# Insert an active Metformin prescription for Denny Lubowitz
# rx table: rxl_id, pid, id, rxl_date_active, drug_name, rxl_sig, rxl_route, drug_dosage, rxl_quantity, rxl_refill, rxl_date_inactive, rxl_reason, practice_id
docker exec nosh-db mysql -uroot -prootpassword nosh -e \
  "INSERT INTO rx_list (pid, id, rxl_date_active, rxl_medication, rxl_dosage, rxl_dosage_unit, rxl_sig, rxl_route, rxl_quantity, rxl_refill, rxl_date_inactive) VALUES (8, 2, CURDATE(), 'Metformin', '500', 'mg', 'Take one tablet by mouth twice daily with meals', 'Oral', '60', '5', NULL);" 2>/dev/null || true

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

echo "=== Task setup complete: discontinue_medication ==="
echo "Metformin 500mg prescription pre-inserted for Denny Lubowitz (pid=8)."
echo "NOSH login page is open. Agent should log in as demo_provider and discontinue the Metformin prescription."
