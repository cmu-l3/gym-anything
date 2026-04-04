#!/bin/bash
# Setup task: post_visit_documentation_workflow
# Patient: Chloe Rafferty (pid=31), female, DOB: 2001-04-18
# Agent must complete 6 documentation tasks after a walk-in visit
echo "=== Setting up post_visit_documentation_workflow task ==="

TASK_NAME="post_visit_documentation_workflow"

# ----------------------------------------------------------------
# 1. Clean up any prior state for pid 31
# ----------------------------------------------------------------
docker exec nosh-db mysql -uroot -prootpassword nosh -e "
DELETE FROM schedule WHERE pid=31;
DELETE FROM vitals WHERE pid=31;
DELETE FROM encounters WHERE pid=31;
DELETE FROM rx WHERE pid=31;
DELETE FROM allergies WHERE pid=31;
DELETE FROM immunizations WHERE pid=31;
DELETE FROM issues WHERE pid=31;
DELETE FROM demographics_relate WHERE pid=31;
DELETE FROM demographics WHERE pid=31;
" 2>/dev/null || true

sleep 1

# ----------------------------------------------------------------
# 2. Seed patient (Chloe Rafferty)
# ----------------------------------------------------------------
docker exec nosh-db mysql -uroot -prootpassword nosh -e "
INSERT INTO demographics (pid, id, lastname, firstname, middle, sex, DOB, address, city, state, zip, phone_home, phone_cell, email, race, ethnicity, language, marital_status, active, date) VALUES
(31, 2, 'Rafferty', 'Chloe', 'K', 'f', '2001-04-18', '12 Meadow View Dr', 'Springfield', 'MA', '01108', '413-555-3031', '413-555-4031', 'chloe.rafferty@example.com', 'White', 'NonHispanic', 'English', 'Single', 1, NOW());

INSERT IGNORE INTO demographics_relate (pid, id, practice_id) VALUES (31, 2, 1);
" 2>/dev/null || true

# ----------------------------------------------------------------
# 3. Record baseline state
# ----------------------------------------------------------------
INIT_ENC=$(docker exec nosh-db mysql -uroot -prootpassword nosh -N -B -e "SELECT COUNT(*) FROM encounters WHERE pid=31;" 2>/dev/null || echo "0")
INIT_VIT=$(docker exec nosh-db mysql -uroot -prootpassword nosh -N -B -e "SELECT COUNT(*) FROM vitals WHERE pid=31;" 2>/dev/null || echo "0")
INIT_ISS=$(docker exec nosh-db mysql -uroot -prootpassword nosh -N -B -e "SELECT COUNT(*) FROM issues WHERE pid=31;" 2>/dev/null || echo "0")
INIT_ALL=$(docker exec nosh-db mysql -uroot -prootpassword nosh -N -B -e "SELECT COUNT(*) FROM allergies WHERE pid=31;" 2>/dev/null || echo "0")
INIT_RX=$(docker exec nosh-db mysql -uroot -prootpassword nosh -N -B -e "SELECT COUNT(*) FROM rx WHERE pid=31;" 2>/dev/null || echo "0")
INIT_SCH=$(docker exec nosh-db mysql -uroot -prootpassword nosh -N -B -e "SELECT COUNT(*) FROM schedule WHERE pid=31;" 2>/dev/null || echo "0")

echo "$INIT_ENC" > /tmp/${TASK_NAME}_init_enc
echo "$INIT_VIT" > /tmp/${TASK_NAME}_init_vit
echo "$INIT_ISS" > /tmp/${TASK_NAME}_init_iss
echo "$INIT_ALL" > /tmp/${TASK_NAME}_init_all
echo "$INIT_RX"  > /tmp/${TASK_NAME}_init_rx
echo "$INIT_SCH" > /tmp/${TASK_NAME}_init_sch
date +%s > /tmp/${TASK_NAME}_start_ts

# ----------------------------------------------------------------
# 4. Launch Firefox
# ----------------------------------------------------------------
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

echo "=== Task setup complete: ${TASK_NAME} ==="
echo "Patient: Chloe Rafferty (pid=31), DOB: 2001-04-18, Sex: F"
echo "Agent must complete 6 documentation tasks:"
echo "  1. Create encounter (Office Visit, today)"
echo "  2. Vitals: weight 134 lbs, height 65 in, BP 112/72, pulse 74, temp 99.1 F"
echo "  3. Problem: J06.9 Acute upper respiratory infection"
echo "  4. Allergy: Penicillin (reaction: Hives)"
echo "  5. Rx: Azithromycin 500mg, 1 tab daily x5 days, qty 5"
echo "  6. Appointment: 2026-07-08 at 10:00 AM, Dr. James Carter"
