#!/bin/bash
# Setup task: diabetic_care_gap_intervention
# Seeds 5 patients with T2DM (pids 36-40):
#   pids 36, 37, 38 = care gaps: no flu vaccine + no recent encounter (agent must intervene)
#   pids 39, 40     = up to date (noise - agent must NOT add duplicates)
echo "=== Setting up diabetic_care_gap_intervention task ==="

TASK_NAME="diabetic_care_gap_intervention"

# ----------------------------------------------------------------
# 1. Clean up prior state
# ----------------------------------------------------------------
docker exec nosh-db mysql -uroot -prootpassword nosh -e "
DELETE FROM schedule WHERE pid IN (36,37,38,39,40);
DELETE FROM vitals WHERE pid IN (36,37,38,39,40);
DELETE FROM encounters WHERE pid IN (36,37,38,39,40);
DELETE FROM rx WHERE pid IN (36,37,38,39,40);
DELETE FROM allergies WHERE pid IN (36,37,38,39,40);
DELETE FROM immunizations WHERE pid IN (36,37,38,39,40);
DELETE FROM issues WHERE pid IN (36,37,38,39,40);
DELETE FROM demographics_relate WHERE pid IN (36,37,38,39,40);
DELETE FROM demographics WHERE pid IN (36,37,38,39,40);
" 2>/dev/null || true

sleep 1

# ----------------------------------------------------------------
# 2. Seed patient demographics
# ----------------------------------------------------------------
docker exec nosh-db mysql -uroot -prootpassword nosh -e "
INSERT INTO demographics (pid, id, lastname, firstname, middle, sex, DOB, address, city, state, zip, phone_home, phone_cell, email, race, ethnicity, language, marital_status, active, date) VALUES
(36, 2, 'Pratt',   'Sandra',  'B', 'f', '1958-11-22', '7 Ashwood Ct',    'Springfield', 'MA', '01105', '413-555-3036', '413-555-4036', 'sandra.pratt@example.com',  'White',    'NonHispanic', 'English', 'Married', 1, NOW()),
(37, 2, 'Holt',    'Gregory', 'E', 'm', '1952-06-17', '45 Meadow Ln',    'Holyoke',     'MA', '01040', '413-555-3037', '413-555-4037', 'gregory.holt@example.com',  'White',    'NonHispanic', 'English', 'Married', 1, NOW()),
(38, 2, 'Kaufman', 'Wendy',   'A', 'f', '1960-03-08', '91 Pine Ridge Dr','Chicopee',    'MA', '01020', '413-555-3038', '413-555-4038', 'wendy.kaufman@example.com', 'White',    'NonHispanic', 'English', 'Divorced', 1, NOW()),
(39, 2, 'Peck',    'Donald',  'R', 'm', '1955-09-14', '23 Oak Hollow Rd','Westfield',   'MA', '01085', '413-555-3039', '413-555-4039', 'donald.peck@example.com',   'White',    'NonHispanic', 'English', 'Married', 1, NOW()),
(40, 2, 'Foley',   'Irene',   'C', 'f', '1963-07-25', '16 Sunridge Ave', 'Northampton', 'MA', '01060', '413-555-3040', '413-555-4040', 'irene.foley@example.com',   'White',    'NonHispanic', 'English', 'Married', 1, NOW())
;" 2>/dev/null || true

docker exec nosh-db mysql -uroot -prootpassword nosh -e "
INSERT IGNORE INTO demographics_relate (pid, id, practice_id)
SELECT pid, 2, 1 FROM demographics WHERE pid IN (36,37,38,39,40);
" 2>/dev/null || true

# ----------------------------------------------------------------
# 3. Seed T2DM diagnosis for all 5 patients
# ----------------------------------------------------------------
docker exec nosh-db mysql -uroot -prootpassword nosh -e "
INSERT INTO issues (pid, issue_date, type, diagnosis, diagnosis_name, activity, description, provider_id, practice_id) VALUES
(36, '2019-04-10', 'medical_problem', 'E11.9', 'Type 2 diabetes mellitus without complications', 'y', 'Type 2 Diabetes Mellitus', 2, 1),
(37, '2017-08-23', 'medical_problem', 'E11.9', 'Type 2 diabetes mellitus without complications', 'y', 'Type 2 Diabetes Mellitus', 2, 1),
(38, '2020-01-15', 'medical_problem', 'E11.9', 'Type 2 diabetes mellitus without complications', 'y', 'Type 2 Diabetes Mellitus', 2, 1),
(39, '2016-06-30', 'medical_problem', 'E11.9', 'Type 2 diabetes mellitus without complications', 'y', 'Type 2 Diabetes Mellitus', 2, 1),
(40, '2018-11-12', 'medical_problem', 'E11.9', 'Type 2 diabetes mellitus without complications', 'y', 'Type 2 Diabetes Mellitus', 2, 1)
;" 2>/dev/null || true

# ----------------------------------------------------------------
# 4. Seed immunization and encounter records
#    pids 36, 37, 38: NO flu vaccine, NO recent encounter (care gaps)
#    pids 39, 40: have recent flu vaccine AND recent encounter (up to date - noise)
# ----------------------------------------------------------------

# Noise patients: current season flu vaccines and recent encounters
docker exec nosh-db mysql -uroot -prootpassword nosh -e "
-- pid 39: Donald Peck - flu vaccine Oct 2024, encounter Dec 2024
INSERT INTO immunizations (pid, imm_immunization, imm_date, imm_cvx, provider_id, practice_id) VALUES
(39, 'Influenza, seasonal', '2024-10-15', '141', 2, 1);

INSERT INTO encounters (pid, encounter_date, encounter_type, reason, cc, provider_id, practice_id) VALUES
(39, '2024-12-10', 'Office Visit', 'Diabetes follow-up', 'Diabetes management review', 2, 1);

-- pid 40: Irene Foley - flu vaccine Nov 2024, encounter Jan 2025
INSERT INTO immunizations (pid, imm_immunization, imm_date, imm_cvx, provider_id, practice_id) VALUES
(40, 'Influenza, seasonal', '2024-11-01', '141', 2, 1);

INSERT INTO encounters (pid, encounter_date, encounter_type, reason, cc, provider_id, practice_id) VALUES
(40, '2025-01-08', 'Office Visit', 'Diabetes follow-up', 'Annual diabetes review', 2, 1);
" 2>/dev/null || true

# Care gap patients: seed only non-flu vaccines (to give them SOME immunization history, just not flu)
# and give them old (>12 month) encounters to make the gap clear
docker exec nosh-db mysql -uroot -prootpassword nosh -e "
-- pid 36: Sandra Pratt - old encounter from 2023, no flu vaccine
INSERT INTO encounters (pid, encounter_date, encounter_type, reason, cc, provider_id, practice_id) VALUES
(36, '2023-06-15', 'Office Visit', 'Diabetes follow-up', 'Annual diabetes review - over a year ago', 2, 1);

-- pid 37: Gregory Holt - old encounter from 2023, no flu vaccine
INSERT INTO encounters (pid, encounter_date, encounter_type, reason, cc, provider_id, practice_id) VALUES
(37, '2023-09-22', 'Office Visit', 'Diabetes follow-up', 'Diabetes management - over a year ago', 2, 1);

-- pid 38: Wendy Kaufman - old encounter from 2023, no flu vaccine
INSERT INTO encounters (pid, encounter_date, encounter_type, reason, cc, provider_id, practice_id) VALUES
(38, '2023-11-05', 'Office Visit', 'Diabetes follow-up', 'Diabetes check - over a year ago', 2, 1);
" 2>/dev/null || true

# ----------------------------------------------------------------
# 5. Record baseline state
# ----------------------------------------------------------------
INIT_IMM36=$(docker exec nosh-db mysql -uroot -prootpassword nosh -N -B -e "SELECT COUNT(*) FROM immunizations WHERE pid=36;" 2>/dev/null || echo "0")
INIT_IMM37=$(docker exec nosh-db mysql -uroot -prootpassword nosh -N -B -e "SELECT COUNT(*) FROM immunizations WHERE pid=37;" 2>/dev/null || echo "0")
INIT_IMM38=$(docker exec nosh-db mysql -uroot -prootpassword nosh -N -B -e "SELECT COUNT(*) FROM immunizations WHERE pid=38;" 2>/dev/null || echo "0")
INIT_ENC36=$(docker exec nosh-db mysql -uroot -prootpassword nosh -N -B -e "SELECT COUNT(*) FROM encounters WHERE pid=36;" 2>/dev/null || echo "0")
INIT_ENC37=$(docker exec nosh-db mysql -uroot -prootpassword nosh -N -B -e "SELECT COUNT(*) FROM encounters WHERE pid=37;" 2>/dev/null || echo "0")
INIT_ENC38=$(docker exec nosh-db mysql -uroot -prootpassword nosh -N -B -e "SELECT COUNT(*) FROM encounters WHERE pid=38;" 2>/dev/null || echo "0")

echo "$INIT_IMM36" > /tmp/${TASK_NAME}_init_imm36
echo "$INIT_IMM37" > /tmp/${TASK_NAME}_init_imm37
echo "$INIT_IMM38" > /tmp/${TASK_NAME}_init_imm38
echo "$INIT_ENC36" > /tmp/${TASK_NAME}_init_enc36
echo "$INIT_ENC37" > /tmp/${TASK_NAME}_init_enc37
echo "$INIT_ENC38" > /tmp/${TASK_NAME}_init_enc38
date +%s > /tmp/${TASK_NAME}_start_ts

# ----------------------------------------------------------------
# 6. Launch Firefox
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
echo "Diabetic patients with care gaps (flu vaccine + encounter needed):"
echo "  pid 36: Sandra Pratt   (DOB: 1958-11-22) — no flu vaccine, last encounter Jun 2023"
echo "  pid 37: Gregory Holt   (DOB: 1952-06-17) — no flu vaccine, last encounter Sep 2023"
echo "  pid 38: Wendy Kaufman  (DOB: 1960-03-08) — no flu vaccine, last encounter Nov 2023"
echo "Noise (already up to date - do NOT add duplicates):"
echo "  pid 39: Donald Peck    (DOB: 1955-09-14) — flu Oct 2024, encounter Dec 2024"
echo "  pid 40: Irene Foley    (DOB: 1963-07-25) — flu Nov 2024, encounter Jan 2025"
