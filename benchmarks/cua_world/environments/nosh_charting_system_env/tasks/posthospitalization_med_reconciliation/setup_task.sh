#!/bin/bash
# Setup task: posthospitalization_med_reconciliation
# Target patient: Sherill Botsford (pid=10, DOB: 1995-01-24)
# Pre-seeds Lisinopril 5mg + Amlodipine 5mg (pre-admission doses to be reconciled)
# Start state: NOSH login page
echo "=== Setting up posthospitalization_med_reconciliation task ==="

# Clean prior task artifacts for this patient
docker exec nosh-db mysql -uroot -prootpassword nosh -e \
  "DELETE FROM rx_list WHERE pid=10 AND UPPER(rxl_medication) IN ('LISINOPRIL','AMLODIPINE') OR (pid=10 AND UPPER(rxl_medication) LIKE '%LISINOPRIL%') OR (pid=10 AND UPPER(rxl_medication) LIKE '%AMLODIPINE%');" 2>/dev/null || true
docker exec nosh-db mysql -uroot -prootpassword nosh -e \
  "DELETE FROM encounters WHERE pid=10;" 2>/dev/null || true

# Seed pre-admission Lisinopril 5mg (active, no inactive date)
docker exec nosh-db mysql -uroot -prootpassword nosh -e \
  "INSERT INTO rx_list (pid, id, rxl_date_active, rxl_medication, rxl_dosage, rxl_dosage_unit, rxl_sig, rxl_route, rxl_quantity, rxl_refill, rxl_date_inactive)
   VALUES (10, 2, DATE_SUB(CURDATE(), INTERVAL 90 DAY), 'Lisinopril', '5', 'mg', 'Take one tablet by mouth daily', 'Oral', '90', '3', NULL);" 2>/dev/null || true

# Seed pre-admission Amlodipine 5mg (active, no inactive date)
docker exec nosh-db mysql -uroot -prootpassword nosh -e \
  "INSERT INTO rx_list (pid, id, rxl_date_active, rxl_medication, rxl_dosage, rxl_dosage_unit, rxl_sig, rxl_route, rxl_quantity, rxl_refill, rxl_date_inactive)
   VALUES (10, 2, DATE_SUB(CURDATE(), INTERVAL 90 DAY), 'Amlodipine', '5', 'mg', 'Take one tablet by mouth daily', 'Oral', '30', '3', NULL);" 2>/dev/null || true

# Record baseline state for verification
echo "$(date +%s)" > /tmp/phmr_start_time.txt
INIT_ENC=$(docker exec nosh-db mysql -uroot -prootpassword nosh -N -e \
  "SELECT COUNT(*) FROM encounters WHERE pid=10;" 2>/dev/null || echo "0")
echo "${INIT_ENC:-0}" > /tmp/phmr_init_enc.txt

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

echo "=== Task setup complete: posthospitalization_med_reconciliation ==="
echo "Seeded: Lisinopril 5mg (active) + Amlodipine 5mg (active) for Sherill Botsford (pid=10)."
echo "Agent must: discontinue both 5mg doses, add Lisinopril 10mg + Amlodipine 10mg, create encounter."
