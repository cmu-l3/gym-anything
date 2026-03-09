#!/bin/bash
# Setup task: hypertension_panel_remediation
# Seeds 5 hypertensive patients: pids 22-26
# pids 22, 23, 24 = untreated hypertension (agent must prescribe Amlodipine + encounter)
# pids 25, 26     = already treated (noise - agent must NOT touch them)
echo "=== Setting up hypertension_panel_remediation task ==="

TASK_NAME="hypertension_panel_remediation"

# ----------------------------------------------------------------
# 1. Clean up any prior state for our seeded patients (pids 22-26)
# ----------------------------------------------------------------
docker exec nosh-db mysql -uroot -prootpassword nosh -e "
DELETE FROM schedule WHERE pid IN (22,23,24,25,26);
DELETE FROM vitals WHERE pid IN (22,23,24,25,26);
DELETE FROM encounters WHERE pid IN (22,23,24,25,26);
DELETE FROM rx WHERE pid IN (22,23,24,25,26);
DELETE FROM allergies WHERE pid IN (22,23,24,25,26);
DELETE FROM immunizations WHERE pid IN (22,23,24,25,26);
DELETE FROM issues WHERE pid IN (22,23,24,25,26);
DELETE FROM demographics_relate WHERE pid IN (22,23,24,25,26);
DELETE FROM demographics WHERE pid IN (22,23,24,25,26);
" 2>/dev/null || true

sleep 1

# ----------------------------------------------------------------
# 2. Seed patient demographics
# ----------------------------------------------------------------
docker exec nosh-db mysql -uroot -prootpassword nosh -e "
INSERT INTO demographics (pid, id, lastname, firstname, middle, sex, DOB, address, city, state, zip, phone_home, phone_cell, email, race, ethnicity, language, marital_status, active, date) VALUES
(22, 2, 'Whitfield', 'Eleanor', 'A', 'f', '1962-03-15', '14 Birchwood Ln', 'Springfield', 'MA', '01108', '413-555-3022', '413-555-4022', 'eleanor.whitfield@example.com', 'White', 'NonHispanic', 'English', 'Married', 1, NOW()),
(23, 2, 'Hartley',   'Russell', 'J', 'm', '1955-08-22', '77 Summit Ave',   'Chicopee',    'MA', '01020', '413-555-3023', '413-555-4023', 'russell.hartley@example.com',   'White', 'NonHispanic', 'English', 'Married', 1, NOW()),
(24, 2, 'Toomey',    'Margaret','C', 'f', '1958-11-07', '32 Orchard Rd',   'Holyoke',     'MA', '01040', '413-555-3024', '413-555-4024', 'margaret.toomey@example.com',   'White', 'NonHispanic', 'English', 'Widowed', 1, NOW()),
(25, 2, 'Keane',     'Bernard', 'T', 'm', '1960-04-30', '101 Maple St',    'Ludlow',      'MA', '01056', '413-555-3025', '413-555-4025', 'bernard.keane@example.com',     'White', 'NonHispanic', 'English', 'Married', 1, NOW()),
(26, 2, 'Vance',     'Dolores', 'M', 'f', '1963-09-12', '55 Cedar Ave',    'Westfield',   'MA', '01085', '413-555-3026', '413-555-4026', 'dolores.vance@example.com',     'White', 'NonHispanic', 'English', 'Single',  1, NOW())
;" 2>/dev/null || true

# Link patients to provider (required for NOSH access control)
docker exec nosh-db mysql -uroot -prootpassword nosh -e "
INSERT IGNORE INTO demographics_relate (pid, id, practice_id)
SELECT pid, 2, 1 FROM demographics WHERE pid IN (22,23,24,25,26);
" 2>/dev/null || true

# ----------------------------------------------------------------
# 3. Seed Essential Hypertension (I10) problem for all 5 patients
# ----------------------------------------------------------------
docker exec nosh-db mysql -uroot -prootpassword nosh -e "
INSERT INTO issues (pid, issue_date, type, diagnosis, diagnosis_name, activity, description, provider_id, practice_id) VALUES
(22, '2023-06-10', 'medical_problem', 'I10', 'Essential (primary) hypertension', 'y', 'Essential Hypertension', 2, 1),
(23, '2022-09-14', 'medical_problem', 'I10', 'Essential (primary) hypertension', 'y', 'Essential Hypertension', 2, 1),
(24, '2021-03-22', 'medical_problem', 'I10', 'Essential (primary) hypertension', 'y', 'Essential Hypertension', 2, 1),
(25, '2020-11-05', 'medical_problem', 'I10', 'Essential (primary) hypertension', 'y', 'Essential Hypertension', 2, 1),
(26, '2019-07-18', 'medical_problem', 'I10', 'Essential (primary) hypertension', 'y', 'Essential Hypertension', 2, 1)
;" 2>/dev/null || true

# ----------------------------------------------------------------
# 4. Seed existing medications for noise patients only (25, 26)
#    pids 22, 23, 24 intentionally have NO antihypertensive
# ----------------------------------------------------------------
docker exec nosh-db mysql -uroot -prootpassword nosh -e "
INSERT INTO rx (pid, drug_name, rxl_sig, rxl_dosage, rxl_route, rxl_frequency, rxl_quantity, rxl_refill, rxl_date_prescribed, rxl_active, provider_id, practice_id) VALUES
(25, 'Lisinopril', 'Take 1 tablet by mouth daily', '10mg', 'oral', 'daily', '30', '3', '2024-01-15', 'y', 2, 1),
(26, 'Amlodipine', 'Take 1 tablet by mouth daily', '5mg',  'oral', 'daily', '30', '3', '2024-03-20', 'y', 2, 1)
;" 2>/dev/null || true

# ----------------------------------------------------------------
# 5. Record baseline counts (BEFORE task start)
# ----------------------------------------------------------------
INITIAL_RX_22=$(docker exec nosh-db mysql -uroot -prootpassword nosh -N -B -e "SELECT COUNT(*) FROM rx WHERE pid=22 AND rxl_active='y';" 2>/dev/null || echo "0")
INITIAL_RX_23=$(docker exec nosh-db mysql -uroot -prootpassword nosh -N -B -e "SELECT COUNT(*) FROM rx WHERE pid=23 AND rxl_active='y';" 2>/dev/null || echo "0")
INITIAL_RX_24=$(docker exec nosh-db mysql -uroot -prootpassword nosh -N -B -e "SELECT COUNT(*) FROM rx WHERE pid=24 AND rxl_active='y';" 2>/dev/null || echo "0")
INITIAL_ENC_22=$(docker exec nosh-db mysql -uroot -prootpassword nosh -N -B -e "SELECT COUNT(*) FROM encounters WHERE pid=22;" 2>/dev/null || echo "0")
INITIAL_ENC_23=$(docker exec nosh-db mysql -uroot -prootpassword nosh -N -B -e "SELECT COUNT(*) FROM encounters WHERE pid=23;" 2>/dev/null || echo "0")
INITIAL_ENC_24=$(docker exec nosh-db mysql -uroot -prootpassword nosh -N -B -e "SELECT COUNT(*) FROM encounters WHERE pid=24;" 2>/dev/null || echo "0")

echo "$INITIAL_RX_22"  > /tmp/${TASK_NAME}_init_rx22
echo "$INITIAL_RX_23"  > /tmp/${TASK_NAME}_init_rx23
echo "$INITIAL_RX_24"  > /tmp/${TASK_NAME}_init_rx24
echo "$INITIAL_ENC_22" > /tmp/${TASK_NAME}_init_enc22
echo "$INITIAL_ENC_23" > /tmp/${TASK_NAME}_init_enc23
echo "$INITIAL_ENC_24" > /tmp/${TASK_NAME}_init_enc24
date +%s > /tmp/${TASK_NAME}_start_ts

# ----------------------------------------------------------------
# 6. Launch Firefox to NOSH login page
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
echo "Seeded 5 hypertensive patients (pids 22-26)."
echo "Untreated (agent must prescribe Amlodipine + encounter): Eleanor Whitfield (22), Russell Hartley (23), Margaret Toomey (24)"
echo "Already treated (noise - do NOT touch): Bernard Keane (25, Lisinopril), Dolores Vance (26, Amlodipine)"
