#!/bin/bash
# Setup task: allergy_drug_conflict_resolution
# Seeds 4 patients (pids 32-35):
#   pid 32: Marcus Odom    — sulfonamide allergy + TMP-SMX prescription (CONFLICT)
#   pid 33: Patricia Fenn  — penicillin allergy + amoxicillin prescription (CONFLICT)
#   pid 34: Theodore Ashe  — codeine allergy + codeine prescription (CONFLICT)
#   pid 35: Nancy Briggs   — latex allergy + metformin prescription (NO CONFLICT - noise)
echo "=== Setting up allergy_drug_conflict_resolution task ==="

TASK_NAME="allergy_drug_conflict_resolution"

# ----------------------------------------------------------------
# 1. Clean up prior state
# ----------------------------------------------------------------
docker exec nosh-db mysql -uroot -prootpassword nosh -e "
DELETE FROM schedule WHERE pid IN (32,33,34,35);
DELETE FROM vitals WHERE pid IN (32,33,34,35);
DELETE FROM encounters WHERE pid IN (32,33,34,35);
DELETE FROM rx WHERE pid IN (32,33,34,35);
DELETE FROM allergies WHERE pid IN (32,33,34,35);
DELETE FROM immunizations WHERE pid IN (32,33,34,35);
DELETE FROM issues WHERE pid IN (32,33,34,35);
DELETE FROM demographics_relate WHERE pid IN (32,33,34,35);
DELETE FROM demographics WHERE pid IN (32,33,34,35);
" 2>/dev/null || true

sleep 1

# ----------------------------------------------------------------
# 2. Seed patient demographics
# ----------------------------------------------------------------
docker exec nosh-db mysql -uroot -prootpassword nosh -e "
INSERT INTO demographics (pid, id, lastname, firstname, middle, sex, DOB, address, city, state, zip, phone_home, phone_cell, email, race, ethnicity, language, marital_status, active, date) VALUES
(32, 2, 'Odom',   'Marcus',   'L', 'm', '1972-04-15', '29 Riverside Dr',  'Springfield', 'MA', '01107', '413-555-3032', '413-555-4032', 'marcus.odom@example.com',   'Black',  'NonHispanic', 'English', 'Married', 1, NOW()),
(33, 2, 'Fenn',   'Patricia', 'R', 'f', '1965-09-28', '67 Hilltop Ave',   'Holyoke',     'MA', '01040', '413-555-3033', '413-555-4033', 'patricia.fenn@example.com', 'White',  'NonHispanic', 'English', 'Divorced', 1, NOW()),
(34, 2, 'Ashe',   'Theodore', 'W', 'm', '1980-02-14', '4 Lakeview Ct',    'Chicopee',    'MA', '01020', '413-555-3034', '413-555-4034', 'theodore.ashe@example.com', 'White',  'NonHispanic', 'English', 'Single', 1, NOW()),
(35, 2, 'Briggs', 'Nancy',    'J', 'f', '1970-07-03', '18 Greenfield Rd', 'Westfield',   'MA', '01085', '413-555-3035', '413-555-4035', 'nancy.briggs@example.com',  'White',  'NonHispanic', 'English', 'Married', 1, NOW())
;" 2>/dev/null || true

docker exec nosh-db mysql -uroot -prootpassword nosh -e "
INSERT IGNORE INTO demographics_relate (pid, id, practice_id)
SELECT pid, 2, 1 FROM demographics WHERE pid IN (32,33,34,35);
" 2>/dev/null || true

# ----------------------------------------------------------------
# 3. Seed allergies
# ----------------------------------------------------------------
docker exec nosh-db mysql -uroot -prootpassword nosh -e "
-- pid 32: sulfonamide allergy
INSERT INTO allergies (pid, allergen, allergy_type, allergy_reaction, allergy_severity, provider_id, practice_id) VALUES
(32, 'Sulfonamides', 'Drug', 'Rash, hives', 'Moderate', 2, 1);

-- pid 33: penicillin allergy
INSERT INTO allergies (pid, allergen, allergy_type, allergy_reaction, allergy_severity, provider_id, practice_id) VALUES
(33, 'Penicillin', 'Drug', 'Anaphylaxis', 'Severe', 2, 1);

-- pid 34: codeine allergy
INSERT INTO allergies (pid, allergen, allergy_type, allergy_reaction, allergy_severity, provider_id, practice_id) VALUES
(34, 'Codeine', 'Drug', 'Urticaria, pruritus', 'Moderate', 2, 1);

-- pid 35: latex allergy (noise - does not conflict with metformin)
INSERT INTO allergies (pid, allergen, allergy_type, allergy_reaction, allergy_severity, provider_id, practice_id) VALUES
(35, 'Latex', 'Environmental', 'Contact dermatitis', 'Mild', 2, 1);
" 2>/dev/null || true

# ----------------------------------------------------------------
# 4. Seed conflicting medications and the noise medication
# ----------------------------------------------------------------
docker exec nosh-db mysql -uroot -prootpassword nosh -e "
-- pid 32: TMP-SMX (sulfonamide conflict)
INSERT INTO rx (pid, drug_name, rxl_sig, rxl_dosage, rxl_route, rxl_frequency, rxl_quantity, rxl_refill, rxl_date_prescribed, rxl_active, provider_id, practice_id) VALUES
(32, 'Trimethoprim-Sulfamethoxazole (TMP-SMX)', 'Take 1 tablet twice daily', '800/160mg', 'oral', 'twice daily', '20', '0', '2025-12-01', 'y', 2, 1);

-- pid 33: Amoxicillin (penicillin conflict)
INSERT INTO rx (pid, drug_name, rxl_sig, rxl_dosage, rxl_route, rxl_frequency, rxl_quantity, rxl_refill, rxl_date_prescribed, rxl_active, provider_id, practice_id) VALUES
(33, 'Amoxicillin', 'Take 1 capsule three times daily', '500mg', 'oral', 'three times daily', '21', '0', '2025-11-20', 'y', 2, 1);

-- pid 34: Codeine (direct conflict)
INSERT INTO rx (pid, drug_name, rxl_sig, rxl_dosage, rxl_route, rxl_frequency, rxl_quantity, rxl_refill, rxl_date_prescribed, rxl_active, provider_id, practice_id) VALUES
(34, 'Codeine Phosphate', 'Take 1 tablet every 4-6 hours as needed for pain', '30mg', 'oral', 'every 4-6 hours PRN', '30', '0', '2025-10-15', 'y', 2, 1);

-- pid 35: Metformin (NO conflict with latex - noise)
INSERT INTO rx (pid, drug_name, rxl_sig, rxl_dosage, rxl_route, rxl_frequency, rxl_quantity, rxl_refill, rxl_date_prescribed, rxl_active, provider_id, practice_id) VALUES
(35, 'Metformin', 'Take 1 tablet twice daily with meals', '500mg', 'oral', 'twice daily', '60', '3', '2025-09-10', 'y', 2, 1);
" 2>/dev/null || true

# ----------------------------------------------------------------
# 5. Record baseline state
# ----------------------------------------------------------------
# We need the initial rx_id for each conflicting medication to check if it was inactivated
INIT_ACTIVE_RX32=$(docker exec nosh-db mysql -uroot -prootpassword nosh -N -B -e "SELECT COUNT(*) FROM rx WHERE pid=32 AND rxl_active='y';" 2>/dev/null || echo "0")
INIT_ACTIVE_RX33=$(docker exec nosh-db mysql -uroot -prootpassword nosh -N -B -e "SELECT COUNT(*) FROM rx WHERE pid=33 AND rxl_active='y';" 2>/dev/null || echo "0")
INIT_ACTIVE_RX34=$(docker exec nosh-db mysql -uroot -prootpassword nosh -N -B -e "SELECT COUNT(*) FROM rx WHERE pid=34 AND rxl_active='y';" 2>/dev/null || echo "0")
INIT_TOTAL_RX32=$(docker exec nosh-db mysql -uroot -prootpassword nosh -N -B -e "SELECT COUNT(*) FROM rx WHERE pid=32;" 2>/dev/null || echo "0")
INIT_TOTAL_RX33=$(docker exec nosh-db mysql -uroot -prootpassword nosh -N -B -e "SELECT COUNT(*) FROM rx WHERE pid=33;" 2>/dev/null || echo "0")
INIT_TOTAL_RX34=$(docker exec nosh-db mysql -uroot -prootpassword nosh -N -B -e "SELECT COUNT(*) FROM rx WHERE pid=34;" 2>/dev/null || echo "0")
INIT_ENC32=$(docker exec nosh-db mysql -uroot -prootpassword nosh -N -B -e "SELECT COUNT(*) FROM encounters WHERE pid=32;" 2>/dev/null || echo "0")
INIT_ENC33=$(docker exec nosh-db mysql -uroot -prootpassword nosh -N -B -e "SELECT COUNT(*) FROM encounters WHERE pid=33;" 2>/dev/null || echo "0")
INIT_ENC34=$(docker exec nosh-db mysql -uroot -prootpassword nosh -N -B -e "SELECT COUNT(*) FROM encounters WHERE pid=34;" 2>/dev/null || echo "0")

echo "$INIT_ACTIVE_RX32" > /tmp/${TASK_NAME}_init_active_rx32
echo "$INIT_ACTIVE_RX33" > /tmp/${TASK_NAME}_init_active_rx33
echo "$INIT_ACTIVE_RX34" > /tmp/${TASK_NAME}_init_active_rx34
echo "$INIT_TOTAL_RX32"  > /tmp/${TASK_NAME}_init_total_rx32
echo "$INIT_TOTAL_RX33"  > /tmp/${TASK_NAME}_init_total_rx33
echo "$INIT_TOTAL_RX34"  > /tmp/${TASK_NAME}_init_total_rx34
echo "$INIT_ENC32"       > /tmp/${TASK_NAME}_init_enc32
echo "$INIT_ENC33"       > /tmp/${TASK_NAME}_init_enc33
echo "$INIT_ENC34"       > /tmp/${TASK_NAME}_init_enc34
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
echo "Patients with allergy-drug conflicts (agent must discover and resolve):"
echo "  pid 32: Marcus Odom    — Sulfonamide allergy + TMP-SMX (CONFLICT)"
echo "  pid 33: Patricia Fenn  — Penicillin allergy + Amoxicillin (CONFLICT)"
echo "  pid 34: Theodore Ashe  — Codeine allergy + Codeine Phosphate (CONFLICT)"
echo "Noise (allergy but NO conflict):"
echo "  pid 35: Nancy Briggs   — Latex allergy + Metformin (NO CONFLICT)"
