#!/bin/bash
# Setup task: vaccine_audit_and_schedule
# Seeds 4 senior patients (pids 27-30):
#   pids 27, 28, 29 = missing Shingrix (agent must add vaccine + schedule appointment)
#   pid 30          = already has Shingrix (noise - do NOT add again)
echo "=== Setting up vaccine_audit_and_schedule task ==="

TASK_NAME="vaccine_audit_and_schedule"

# ----------------------------------------------------------------
# 1. Clean up prior state
# ----------------------------------------------------------------
docker exec nosh-db mysql -uroot -prootpassword nosh -e "
DELETE FROM schedule WHERE pid IN (27,28,29,30);
DELETE FROM immunizations WHERE pid IN (27,28,29,30);
DELETE FROM vitals WHERE pid IN (27,28,29,30);
DELETE FROM encounters WHERE pid IN (27,28,29,30);
DELETE FROM rx WHERE pid IN (27,28,29,30);
DELETE FROM issues WHERE pid IN (27,28,29,30);
DELETE FROM demographics_relate WHERE pid IN (27,28,29,30);
DELETE FROM demographics WHERE pid IN (27,28,29,30);
" 2>/dev/null || true

sleep 1

# ----------------------------------------------------------------
# 2. Seed patient demographics (elderly patients)
# ----------------------------------------------------------------
docker exec nosh-db mysql -uroot -prootpassword nosh -e "
INSERT INTO demographics (pid, id, lastname, firstname, middle, sex, DOB, address, city, state, zip, phone_home, phone_cell, email, race, ethnicity, language, marital_status, active, date) VALUES
(27, 2, 'Slagle', 'Virginia', 'E', 'f', '1948-06-10', '22 Heritage Ln',  'Northampton', 'MA', '01060', '413-555-3027', '413-555-4027', 'virginia.slagle@example.com', 'White', 'NonHispanic', 'English', 'Widowed',  1, NOW()),
(28, 2, 'Dunbar', 'Harold',   'R', 'm', '1945-11-23', '8 Veterans Way',  'Amherst',     'MA', '01002', '413-555-3028', '413-555-4028', 'harold.dunbar@example.com',   'White', 'NonHispanic', 'English', 'Married',  1, NOW()),
(29, 2, 'Morley', 'Agnes',    'L', 'f', '1951-08-04', '56 Elm Park Rd',  'Greenfield',  'MA', '01301', '413-555-3029', '413-555-4029', 'agnes.morley@example.com',    'White', 'NonHispanic', 'English', 'Widowed',  1, NOW()),
(30, 2, 'Webb',   'Clarence', 'F', 'm', '1950-03-17', '103 Colonial Dr', 'Pittsfield',  'MA', '01201', '413-555-3030', '413-555-4030', 'clarence.webb@example.com',   'White', 'NonHispanic', 'English', 'Married',  1, NOW())
;" 2>/dev/null || true

docker exec nosh-db mysql -uroot -prootpassword nosh -e "
INSERT IGNORE INTO demographics_relate (pid, id, practice_id)
SELECT pid, 2, 1 FROM demographics WHERE pid IN (27,28,29,30);
" 2>/dev/null || true

# ----------------------------------------------------------------
# 3. Seed immunization histories
#    pids 27, 29 = have Influenza + Pneumovax, missing Shingrix
#    pid 28      = has Influenza only, missing Shingrix
#    pid 30      = has all three (noise - fully up to date)
# ----------------------------------------------------------------
docker exec nosh-db mysql -uroot -prootpassword nosh -e "
-- pid 27: Virginia Slagle — has Influenza + Pneumovax, missing Shingrix
INSERT INTO immunizations (pid, imm_immunization, imm_date, imm_cvx, provider_id, practice_id) VALUES
(27, 'Influenza, seasonal', '2024-10-03', '141', 2, 1),
(27, 'Pneumococcal polysaccharide PPV23', '2022-09-12', '33', 2, 1);

-- pid 28: Harold Dunbar — has Influenza only, missing Shingrix
INSERT INTO immunizations (pid, imm_immunization, imm_date, imm_cvx, provider_id, practice_id) VALUES
(28, 'Influenza, seasonal', '2024-11-07', '141', 2, 1);

-- pid 29: Agnes Morley — has Influenza + Pneumovax, missing Shingrix
INSERT INTO immunizations (pid, imm_immunization, imm_date, imm_cvx, provider_id, practice_id) VALUES
(29, 'Influenza, seasonal', '2024-10-21', '141', 2, 1),
(29, 'Pneumococcal polysaccharide PPV23', '2023-03-08', '33', 2, 1);

-- pid 30: Clarence Webb — fully up to date (noise)
INSERT INTO immunizations (pid, imm_immunization, imm_date, imm_cvx, provider_id, practice_id) VALUES
(30, 'Influenza, seasonal', '2024-10-15', '141', 2, 1),
(30, 'Pneumococcal polysaccharide PPV23', '2021-11-30', '33', 2, 1),
(30, 'Zoster (Shingrix)', '2023-05-22', '187', 2, 1);
" 2>/dev/null || true

# ----------------------------------------------------------------
# 4. Record baseline state
# ----------------------------------------------------------------
INIT_IMM27=$(docker exec nosh-db mysql -uroot -prootpassword nosh -N -B -e "SELECT COUNT(*) FROM immunizations WHERE pid=27;" 2>/dev/null || echo "0")
INIT_IMM28=$(docker exec nosh-db mysql -uroot -prootpassword nosh -N -B -e "SELECT COUNT(*) FROM immunizations WHERE pid=28;" 2>/dev/null || echo "0")
INIT_IMM29=$(docker exec nosh-db mysql -uroot -prootpassword nosh -N -B -e "SELECT COUNT(*) FROM immunizations WHERE pid=29;" 2>/dev/null || echo "0")
INIT_IMM30=$(docker exec nosh-db mysql -uroot -prootpassword nosh -N -B -e "SELECT COUNT(*) FROM immunizations WHERE pid=30;" 2>/dev/null || echo "0")
INIT_SCH27=$(docker exec nosh-db mysql -uroot -prootpassword nosh -N -B -e "SELECT COUNT(*) FROM schedule WHERE pid=27;" 2>/dev/null || echo "0")
INIT_SCH28=$(docker exec nosh-db mysql -uroot -prootpassword nosh -N -B -e "SELECT COUNT(*) FROM schedule WHERE pid=28;" 2>/dev/null || echo "0")
INIT_SCH29=$(docker exec nosh-db mysql -uroot -prootpassword nosh -N -B -e "SELECT COUNT(*) FROM schedule WHERE pid=29;" 2>/dev/null || echo "0")

echo "$INIT_IMM27" > /tmp/${TASK_NAME}_init_imm27
echo "$INIT_IMM28" > /tmp/${TASK_NAME}_init_imm28
echo "$INIT_IMM29" > /tmp/${TASK_NAME}_init_imm29
echo "$INIT_IMM30" > /tmp/${TASK_NAME}_init_imm30
echo "$INIT_SCH27" > /tmp/${TASK_NAME}_init_sch27
echo "$INIT_SCH28" > /tmp/${TASK_NAME}_init_sch28
echo "$INIT_SCH29" > /tmp/${TASK_NAME}_init_sch29
date +%s > /tmp/${TASK_NAME}_start_ts

# ----------------------------------------------------------------
# 5. Launch Firefox
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
echo "Senior patients missing Shingrix (agent must add vaccine + schedule 2026-09-15 9:00 AM):"
echo "  pid 27: Virginia Slagle (DOB: 1948-06-10) — has flu + pneumovax, missing Shingrix"
echo "  pid 28: Harold Dunbar   (DOB: 1945-11-23) — has flu only, missing Shingrix"
echo "  pid 29: Agnes Morley    (DOB: 1951-08-04) — has flu + pneumovax, missing Shingrix"
echo "Noise (fully vaccinated - do NOT re-vaccinate):"
echo "  pid 30: Clarence Webb   (DOB: 1950-03-17) — has all vaccines including Shingrix"
