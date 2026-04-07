#!/bin/bash
# Setup task: new_patient_intake
# Target patient: Hobert Wuckert (pid=11, DOB: 2000-10-27) - new patient, no prior records
# Start state: NOSH login page
echo "=== Setting up new_patient_intake task ==="

# Clean any prior artifacts for this patient to create a clean new patient experience
docker exec nosh-db mysql -uroot -prootpassword nosh -e \
  "DELETE FROM other_history WHERE pid=11;" 2>/dev/null || true
docker exec nosh-db mysql -uroot -prootpassword nosh -e \
  "DELETE FROM insurance WHERE pid=11;" 2>/dev/null || true
docker exec nosh-db mysql -uroot -prootpassword nosh -e \
  "DELETE FROM encounters WHERE pid=11;" 2>/dev/null || true

# Record baseline state for anti-gaming verification
echo "$(date +%s)" > /tmp/npi_start_time.txt
echo "0" > /tmp/npi_init_history.txt
echo "0" > /tmp/npi_init_insurance.txt
echo "0" > /tmp/npi_init_enc.txt

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

echo "=== Task setup complete: new_patient_intake ==="
echo "Hobert Wuckert (pid=11) has no prior history, insurance, or encounters."
echo "Agent must complete full new patient intake: social history, family history, insurance, encounter."
