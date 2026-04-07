#!/bin/bash
# Setup task: comprehensive_chronic_disease_visit
# Target patient: Kelle Crist (pid=9, DOB: 2002-10-18)
# Start state: NOSH login page, patient chart clean (no prior encounters/orders/meds for this task)
echo "=== Setting up comprehensive_chronic_disease_visit task ==="

# Clean any prior task artifacts for this patient
docker exec nosh-db mysql -uroot -prootpassword nosh -e \
  "DELETE FROM encounters WHERE pid=9;" 2>/dev/null || true
docker exec nosh-db mysql -uroot -prootpassword nosh -e \
  "DELETE FROM orders WHERE pid=9;" 2>/dev/null || true
docker exec nosh-db mysql -uroot -prootpassword nosh -e \
  "DELETE FROM rx_list WHERE pid=9 AND UPPER(rxl_medication) LIKE '%METFORMIN%';" 2>/dev/null || true

# Record baseline counts for anti-gaming verification
INIT_ENC=$(docker exec nosh-db mysql -uroot -prootpassword nosh -N -e \
  "SELECT COUNT(*) FROM encounters WHERE pid=9;" 2>/dev/null || echo "0")
INIT_ORD=$(docker exec nosh-db mysql -uroot -prootpassword nosh -N -e \
  "SELECT COUNT(*) FROM orders WHERE pid=9;" 2>/dev/null || echo "0")
INIT_RX=$(docker exec nosh-db mysql -uroot -prootpassword nosh -N -e \
  "SELECT COUNT(*) FROM rx_list WHERE pid=9;" 2>/dev/null || echo "0")

echo "${INIT_ENC:-0}" > /tmp/ccdv_init_enc.txt
echo "${INIT_ORD:-0}" > /tmp/ccdv_init_ord.txt
echo "${INIT_RX:-0}" > /tmp/ccdv_init_rx.txt
echo "$(date +%s)" > /tmp/ccdv_start_time.txt

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

echo "=== Task setup complete: comprehensive_chronic_disease_visit ==="
echo "Patient Kelle Crist (pid=9) chart is clean. NOSH login page is open."
echo "Agent must: create encounter, order HbA1c+CMP labs, place endocrinology referral, add Metformin 500mg."
