#!/bin/bash
# Setup task: medication_safety_review
# Target patient: Cordie King (pid=13, DOB: 1995-03-11)
# Pre-seeds 3 medications: Warfarin 5mg (keep), Aspirin 325mg (discontinue), Ibuprofen 600mg (discontinue)
# The agent must identify the NSAIDs/antiplatelets and discontinue them, then order INR, create encounter
# Start state: NOSH login page
echo "=== Setting up medication_safety_review task ==="

# Clean prior task artifacts for this patient
docker exec nosh-db mysql -uroot -prootpassword nosh -e \
  "DELETE FROM rx_list WHERE pid=13;" 2>/dev/null || true
docker exec nosh-db mysql -uroot -prootpassword nosh -e \
  "DELETE FROM orders WHERE pid=13;" 2>/dev/null || true
docker exec nosh-db mysql -uroot -prootpassword nosh -e \
  "DELETE FROM encounters WHERE pid=13;" 2>/dev/null || true

# Seed Warfarin 5mg daily (active anticoagulant - must NOT be discontinued)
docker exec nosh-db mysql -uroot -prootpassword nosh -e \
  "INSERT INTO rx_list (pid, id, rxl_date_active, rxl_medication, rxl_dosage, rxl_dosage_unit, rxl_sig, rxl_route, rxl_quantity, rxl_refill, rxl_date_inactive)
   VALUES (13, 2, DATE_SUB(CURDATE(), INTERVAL 180 DAY), 'Warfarin', '5', 'mg', 'Take one tablet by mouth daily - ANTICOAGULATION', 'Oral', '90', '5', NULL);" 2>/dev/null || true

# Seed Aspirin 325mg daily (antiplatelet - DANGEROUS with Warfarin, must be discontinued)
docker exec nosh-db mysql -uroot -prootpassword nosh -e \
  "INSERT INTO rx_list (pid, id, rxl_date_active, rxl_medication, rxl_dosage, rxl_dosage_unit, rxl_sig, rxl_route, rxl_quantity, rxl_refill, rxl_date_inactive)
   VALUES (13, 2, DATE_SUB(CURDATE(), INTERVAL 60 DAY), 'Aspirin', '325', 'mg', 'Take one tablet by mouth daily', 'Oral', '30', '0', NULL);" 2>/dev/null || true

# Seed Ibuprofen 600mg TID (NSAID - DANGEROUS with Warfarin, must be discontinued)
docker exec nosh-db mysql -uroot -prootpassword nosh -e \
  "INSERT INTO rx_list (pid, id, rxl_date_active, rxl_medication, rxl_dosage, rxl_dosage_unit, rxl_sig, rxl_route, rxl_quantity, rxl_refill, rxl_date_inactive)
   VALUES (13, 2, DATE_SUB(CURDATE(), INTERVAL 30 DAY), 'Ibuprofen', '600', 'mg', 'Take one tablet by mouth three times daily with food', 'Oral', '90', '0', NULL);" 2>/dev/null || true

# Record baseline state for anti-gaming verification
echo "$(date +%s)" > /tmp/msr_start_time.txt
WARFARIN_ID=$(docker exec nosh-db mysql -uroot -prootpassword nosh -N -e \
  "SELECT rxl_id FROM rx_list WHERE pid=13 AND UPPER(rxl_medication) LIKE '%WARFARIN%' LIMIT 1;" 2>/dev/null || echo "")
echo "${WARFARIN_ID:-}" > /tmp/msr_warfarin_id.txt
echo "3" > /tmp/msr_init_rx_count.txt

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

echo "=== Task setup complete: medication_safety_review ==="
echo "Seeded for Cordie King (pid=13): Warfarin 5mg + Aspirin 325mg + Ibuprofen 600mg."
echo "Agent must: identify and discontinue NSAIDs (Aspirin+Ibuprofen), keep Warfarin, order INR, create encounter."
