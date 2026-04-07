#!/bin/bash
# Setup task: care_quality_remediation
# Seeds 6 patients (pids 41-46):
#   pid 41: Helen Mercer      — missing: E11.9 on problem list, Sulfonamide allergy, follow-up appt, encounter
#   pid 42: Frank Costello     — missing: Losartan dose needs update 50mg→100mg, encounter
#   pid 43: Beatrice Yamamoto  — missing: M81.0 on problem list, Alendronate Rx, Iodine allergy, encounter
#   pid 44: Raymond Delacroix  — missing: K21.0 on problem list, Omeprazole Rx, follow-up appt, encounter
#   pid 45: Dorothy Nguyen     — NOISE (all complete, no changes needed)
#   pid 46: Walter Fitzgerald  — NOISE (all complete, no changes needed)
echo "=== Setting up care_quality_remediation task ==="

TASK_NAME="care_quality_remediation"

# ----------------------------------------------------------------
# 1. Clean up any prior state for pids 41-46
# ----------------------------------------------------------------
docker exec nosh-db mysql -uroot -prootpassword nosh -e "
DELETE FROM schedule WHERE pid IN (41,42,43,44,45,46);
DELETE FROM vitals WHERE pid IN (41,42,43,44,45,46);
DELETE FROM encounters WHERE pid IN (41,42,43,44,45,46);
DELETE FROM rx_list WHERE pid IN (41,42,43,44,45,46);
DELETE FROM allergies WHERE pid IN (41,42,43,44,45,46);
DELETE FROM immunizations WHERE pid IN (41,42,43,44,45,46);
DELETE FROM issues WHERE pid IN (41,42,43,44,45,46);
DELETE FROM demographics_relate WHERE pid IN (41,42,43,44,45,46);
DELETE FROM demographics WHERE pid IN (41,42,43,44,45,46);
" 2>/dev/null || true

sleep 1

# ----------------------------------------------------------------
# 2. Seed patient demographics
# ----------------------------------------------------------------
docker exec nosh-db mysql -uroot -prootpassword nosh -e "
INSERT INTO demographics (pid, id, lastname, firstname, middle, sex, DOB, address, city, state, zip, phone_home, phone_cell, email, race, ethnicity, language, marital_status, active, date) VALUES
(41, 2, 'Mercer',     'Helen',    'R', 'f', '1956-08-14', '38 Willow Creek Dr',  'Springfield', 'MA', '01108', '413-555-3041', '413-555-4041', 'helen.mercer@example.com',      'White',    'NonHispanic', 'English', 'Married',  1, NOW()),
(42, 2, 'Costello',   'Frank',    'J', 'm', '1949-03-22', '15 Veterans Pkwy',    'Holyoke',     'MA', '01040', '413-555-3042', '413-555-4042', 'frank.costello@example.com',    'White',    'NonHispanic', 'English', 'Widowed',  1, NOW()),
(43, 2, 'Yamamoto',   'Beatrice', 'K', 'f', '1960-12-01', '220 Cherry Blossom Ln','Chicopee',   'MA', '01020', '413-555-3043', '413-555-4043', 'beatrice.yamamoto@example.com', 'Asian',    'NonHispanic', 'English', 'Married',  1, NOW()),
(44, 2, 'Delacroix',  'Raymond',  'P', 'm', '1952-06-30', '7 Riverside Terrace', 'Westfield',   'MA', '01085', '413-555-3044', '413-555-4044', 'raymond.delacroix@example.com', 'White',    'NonHispanic', 'English', 'Married',  1, NOW()),
(45, 2, 'Nguyen',     'Dorothy',  'L', 'f', '1958-04-18', '91 Pinehill Rd',      'Ludlow',      'MA', '01056', '413-555-3045', '413-555-4045', 'dorothy.nguyen@example.com',    'Asian',    'NonHispanic', 'English', 'Single',   1, NOW()),
(46, 2, 'Fitzgerald', 'Walter',   'T', 'm', '1954-11-05', '44 Brookside Ave',    'Agawam',      'MA', '01001', '413-555-3046', '413-555-4046', 'walter.fitzgerald@example.com', 'White',    'NonHispanic', 'English', 'Divorced', 1, NOW())
;" 2>/dev/null || true

# Link all patients to provider (required for NOSH access control)
docker exec nosh-db mysql -uroot -prootpassword nosh -e "
INSERT IGNORE INTO demographics_relate (pid, id, practice_id)
SELECT pid, 2, 1 FROM demographics WHERE pid IN (41,42,43,44,45,46);
" 2>/dev/null || true

# ----------------------------------------------------------------
# 3. Seed existing problems (what's already on the chart)
#    issues table schema: issue_id, pid, issue, issue_date_active,
#    issue_date_inactive, issue_provider, type, notes, label
# ----------------------------------------------------------------
docker exec nosh-db mysql -uroot -prootpassword nosh -e "
-- pid 41 Helen: NO diabetes problem (that's the gap)

-- pid 42 Frank: CKD Stage 3 exists
INSERT INTO issues (pid, issue, issue_date_active, issue_provider, type, notes) VALUES
(42, 'Chronic kidney disease, stage 3 (moderate) [N18.3]', '2022-04-10', 'James Carter', 'Problem List', 'CKD Stage 3, eGFR 42');

-- pid 43 Beatrice: Hypothyroidism exists, Osteoporosis is MISSING
INSERT INTO issues (pid, issue, issue_date_active, issue_provider, type, notes) VALUES
(43, 'Hypothyroidism, unspecified [E03.9]', '2018-09-05', 'James Carter', 'Problem List', 'Hypothyroidism');

-- pid 44 Raymond: Atrial fibrillation exists, GERD is MISSING
INSERT INTO issues (pid, issue, issue_date_active, issue_provider, type, notes) VALUES
(44, 'Unspecified atrial fibrillation [I48.91]', '2019-11-20', 'James Carter', 'Problem List', 'Atrial Fibrillation');

-- pid 45 Dorothy (noise): Hypertension exists
INSERT INTO issues (pid, issue, issue_date_active, issue_provider, type, notes) VALUES
(45, 'Essential (primary) hypertension [I10]', '2020-06-15', 'James Carter', 'Problem List', 'Essential Hypertension');

-- pid 46 Walter (noise): COPD exists
INSERT INTO issues (pid, issue, issue_date_active, issue_provider, type, notes) VALUES
(46, 'Chronic obstructive pulmonary disease with acute exacerbation [J44.1]', '2017-03-08', 'James Carter', 'Problem List', 'COPD');
" 2>/dev/null || true

# ----------------------------------------------------------------
# 4. Seed existing medications
#    rx_list table schema: rxl_id, pid, rxl_date_active, rxl_date_prescribed,
#    rxl_medication, rxl_dosage, rxl_dosage_unit, rxl_sig, rxl_route,
#    rxl_frequency, rxl_quantity, rxl_refill, rxl_reason, rxl_date_inactive,
#    rxl_provider, id
# ----------------------------------------------------------------
docker exec nosh-db mysql -uroot -prootpassword nosh -e "
-- pid 41 Helen: Metformin exists (correct, no change needed)
INSERT INTO rx_list (pid, rxl_medication, rxl_dosage, rxl_dosage_unit, rxl_sig, rxl_route, rxl_frequency, rxl_quantity, rxl_refill, rxl_date_active, rxl_date_prescribed, rxl_provider, id) VALUES
(41, 'Metformin', '1000', 'mg', 'Take 1 tablet twice daily with meals', 'oral', 'twice daily', '60', '3', '2025-06-15', '2025-06-15', 'James Carter', 2);

-- pid 42 Frank: Losartan at WRONG dose (50mg instead of 100mg)
INSERT INTO rx_list (pid, rxl_medication, rxl_dosage, rxl_dosage_unit, rxl_sig, rxl_route, rxl_frequency, rxl_quantity, rxl_refill, rxl_date_active, rxl_date_prescribed, rxl_provider, id) VALUES
(42, 'Losartan', '50', 'mg', 'Take 1 tablet by mouth daily', 'oral', 'daily', '30', '3', '2025-04-20', '2025-04-20', 'James Carter', 2);

-- pid 43 Beatrice: Levothyroxine exists (correct); Alendronate is MISSING
INSERT INTO rx_list (pid, rxl_medication, rxl_dosage, rxl_dosage_unit, rxl_sig, rxl_route, rxl_frequency, rxl_quantity, rxl_refill, rxl_date_active, rxl_date_prescribed, rxl_provider, id) VALUES
(43, 'Levothyroxine', '75', 'mcg', 'Take 1 tablet by mouth daily on empty stomach', 'oral', 'daily', '30', '3', '2025-03-10', '2025-03-10', 'James Carter', 2);

-- pid 44 Raymond: Warfarin exists (correct); Omeprazole is MISSING
INSERT INTO rx_list (pid, rxl_medication, rxl_dosage, rxl_dosage_unit, rxl_sig, rxl_route, rxl_frequency, rxl_quantity, rxl_refill, rxl_date_active, rxl_date_prescribed, rxl_provider, id) VALUES
(44, 'Warfarin', '5', 'mg', 'Take 1 tablet by mouth daily', 'oral', 'daily', '30', '3', '2025-02-28', '2025-02-28', 'James Carter', 2);

-- pid 45 Dorothy (noise): Amlodipine exists (correct)
INSERT INTO rx_list (pid, rxl_medication, rxl_dosage, rxl_dosage_unit, rxl_sig, rxl_route, rxl_frequency, rxl_quantity, rxl_refill, rxl_date_active, rxl_date_prescribed, rxl_provider, id) VALUES
(45, 'Amlodipine', '5', 'mg', 'Take 1 tablet by mouth daily', 'oral', 'daily', '30', '3', '2025-05-01', '2025-05-01', 'James Carter', 2);

-- pid 46 Walter (noise): Tiotropium exists (correct)
INSERT INTO rx_list (pid, rxl_medication, rxl_dosage, rxl_dosage_unit, rxl_sig, rxl_route, rxl_frequency, rxl_quantity, rxl_refill, rxl_date_active, rxl_date_prescribed, rxl_provider, id) VALUES
(46, 'Tiotropium', '18', 'mcg', 'Inhale 1 capsule daily using HandiHaler', 'inhalation', 'daily', '30', '3', '2025-01-15', '2025-01-15', 'James Carter', 2);
" 2>/dev/null || true

# ----------------------------------------------------------------
# 5. Seed existing allergies
#    allergies table schema: allergies_id, pid, allergies_date_active,
#    allergies_date_inactive, allergies_med, allergies_reaction,
#    allergies_provider, allergies_severity, provider_id
# ----------------------------------------------------------------
docker exec nosh-db mysql -uroot -prootpassword nosh -e "
-- pid 41 Helen: Sulfonamide allergy is MISSING (that's the gap)

-- pid 44 Raymond: Aspirin allergy exists (correct, no change needed)
INSERT INTO allergies (pid, allergies_med, allergies_reaction, allergies_severity, allergies_date_active, allergies_provider, provider_id) VALUES
(44, 'Aspirin', 'GI bleeding', 'Severe', '2020-01-15', 'James Carter', 2);

-- pid 45 Dorothy (noise): Penicillin allergy exists (correct)
INSERT INTO allergies (pid, allergies_med, allergies_reaction, allergies_severity, allergies_date_active, allergies_provider, provider_id) VALUES
(45, 'Penicillin', 'Hives', 'Moderate', '2019-06-10', 'James Carter', 2);
" 2>/dev/null || true

# ----------------------------------------------------------------
# 6. Seed recent encounters for noise patients and Frank (pid 42)
#    Gap patients 41, 44 have NO recent encounters (overdue)
#    encounters table schema: eid, pid, encounter_provider, encounter_date,
#    encounter_type, encounter_cc, encounter_role, practice_id
# ----------------------------------------------------------------
docker exec nosh-db mysql -uroot -prootpassword nosh -e "
-- pid 42 Frank: recent encounter exists (so no appointment needed)
INSERT INTO encounters (pid, encounter_date, encounter_provider, encounter_type, encounter_cc, encounter_role, practice_id) VALUES
(42, DATE_SUB(CURDATE(), INTERVAL 45 DAY), '2', 'Office Visit', 'CKD Stage 3 follow-up. Continue Losartan. Recheck renal panel in 3 months.', 'provider', 1);

-- pid 43 Beatrice: recent encounter exists (so no appointment needed)
INSERT INTO encounters (pid, encounter_date, encounter_provider, encounter_type, encounter_cc, encounter_role, practice_id) VALUES
(43, DATE_SUB(CURDATE(), INTERVAL 30 DAY), '2', 'Office Visit', 'Hypothyroidism follow-up. Stable on current dose. Continue Levothyroxine 75mcg.', 'provider', 1);

-- pid 45 Dorothy (noise): recent encounter
INSERT INTO encounters (pid, encounter_date, encounter_provider, encounter_type, encounter_cc, encounter_role, practice_id) VALUES
(45, DATE_SUB(CURDATE(), INTERVAL 20 DAY), '2', 'Office Visit', 'Hypertension well-controlled on Amlodipine 5mg. Continue current regimen.', 'provider', 1);

-- pid 46 Walter (noise): recent encounter
INSERT INTO encounters (pid, encounter_date, encounter_provider, encounter_type, encounter_cc, encounter_role, practice_id) VALUES
(46, DATE_SUB(CURDATE(), INTERVAL 15 DAY), '2', 'Office Visit', 'COPD stable. No exacerbations. Continue Tiotropium 18mcg daily.', 'provider', 1);
" 2>/dev/null || true

# ----------------------------------------------------------------
# 7. Create the quality review file on Desktop
# ----------------------------------------------------------------
mkdir -p /home/ga/Desktop
cat > /home/ga/Desktop/quality_review.txt << 'QREOF'
HILLSIDE FAMILY MEDICINE
Quarterly Care Quality Review - Q1 2026
Reviewed by: Quality Assurance Team
Date: March 15, 2026

The following patients have been identified with care gaps
requiring provider remediation. Review each patient's chart
and address all listed deficiencies.

------------------------------------------------
PATIENT: Helen Mercer (DOB: 08/14/1956)
GAPS IDENTIFIED:
  1. Diagnosis "Type 2 Diabetes Mellitus" (ICD-10: E11.9)
     not on active problem list despite documented HbA1c
     of 7.8% and active Metformin prescription.
  2. Known Sulfonamide drug allergy (reaction: skin rash,
     moderate severity) not documented in allergy list per
     pharmacy notification.
  3. No follow-up visit scheduled. Last encounter was over
     8 months ago.
     -> Schedule with Dr. James Carter on July 15, 2026
        at 10:00 AM.
------------------------------------------------
PATIENT: Frank Costello (DOB: 03/22/1949)
GAPS IDENTIFIED:
  1. Current Losartan prescription shows 50mg daily.
     Nephrology consult recommended increase to 100mg
     daily per last renal panel (eGFR 42).
     -> Update medication dosage to 100mg daily.
------------------------------------------------
PATIENT: Beatrice Yamamoto (DOB: 12/01/1960)
GAPS IDENTIFIED:
  1. Diagnosis "Osteoporosis" (ICD-10: M81.0) not on
     active problem list despite documented DEXA T-score
     of -2.8.
  2. Alendronate 70mg weekly prescribed by rheumatology
     not entered in medication list.
  3. Known Iodine contrast allergy (reaction: anaphylaxis,
     severe) not documented in allergy list per radiology
     incident report.
------------------------------------------------
PATIENT: Raymond Delacroix (DOB: 06/30/1952)
GAPS IDENTIFIED:
  1. Diagnosis "GERD" (ICD-10: K21.0) not on active
     problem list despite ongoing Omeprazole prescription.
  2. Omeprazole 20mg daily not entered in medication list.
  3. No follow-up visit scheduled. Last cardiology encounter
     was over 7 months ago.
     -> Schedule with Dr. James Carter on July 1, 2026
        at 9:00 AM.
------------------------------------------------
PATIENT: Dorothy Nguyen (DOB: 04/18/1958)
STATUS: All care metrics current. No action required.
------------------------------------------------
PATIENT: Walter Fitzgerald (DOB: 11/05/1954)
STATUS: All care metrics current. No action required.
------------------------------------------------

INSTRUCTIONS: For each patient with gaps, create an
encounter note documenting the remediation actions taken
and clinical rationale.

END OF REPORT
QREOF

chown ga:ga /home/ga/Desktop/quality_review.txt

# ----------------------------------------------------------------
# 8. Record baseline state
# ----------------------------------------------------------------
# Problem list (issues) counts
INIT_ISS_41=$(docker exec nosh-db mysql -uroot -prootpassword nosh -N -B -e "SELECT COUNT(*) FROM issues WHERE pid=41;" 2>/dev/null || echo "0")
INIT_ISS_42=$(docker exec nosh-db mysql -uroot -prootpassword nosh -N -B -e "SELECT COUNT(*) FROM issues WHERE pid=42;" 2>/dev/null || echo "0")
INIT_ISS_43=$(docker exec nosh-db mysql -uroot -prootpassword nosh -N -B -e "SELECT COUNT(*) FROM issues WHERE pid=43;" 2>/dev/null || echo "0")
INIT_ISS_44=$(docker exec nosh-db mysql -uroot -prootpassword nosh -N -B -e "SELECT COUNT(*) FROM issues WHERE pid=44;" 2>/dev/null || echo "0")
INIT_ISS_45=$(docker exec nosh-db mysql -uroot -prootpassword nosh -N -B -e "SELECT COUNT(*) FROM issues WHERE pid=45;" 2>/dev/null || echo "0")
INIT_ISS_46=$(docker exec nosh-db mysql -uroot -prootpassword nosh -N -B -e "SELECT COUNT(*) FROM issues WHERE pid=46;" 2>/dev/null || echo "0")

# Rx counts (rx_list is the individual prescription table)
INIT_RX_41=$(docker exec nosh-db mysql -uroot -prootpassword nosh -N -B -e "SELECT COUNT(*) FROM rx_list WHERE pid=41;" 2>/dev/null || echo "0")
INIT_RX_42=$(docker exec nosh-db mysql -uroot -prootpassword nosh -N -B -e "SELECT COUNT(*) FROM rx_list WHERE pid=42;" 2>/dev/null || echo "0")
INIT_RX_43=$(docker exec nosh-db mysql -uroot -prootpassword nosh -N -B -e "SELECT COUNT(*) FROM rx_list WHERE pid=43;" 2>/dev/null || echo "0")
INIT_RX_44=$(docker exec nosh-db mysql -uroot -prootpassword nosh -N -B -e "SELECT COUNT(*) FROM rx_list WHERE pid=44;" 2>/dev/null || echo "0")
INIT_RX_45=$(docker exec nosh-db mysql -uroot -prootpassword nosh -N -B -e "SELECT COUNT(*) FROM rx_list WHERE pid=45;" 2>/dev/null || echo "0")
INIT_RX_46=$(docker exec nosh-db mysql -uroot -prootpassword nosh -N -B -e "SELECT COUNT(*) FROM rx_list WHERE pid=46;" 2>/dev/null || echo "0")

# Allergy counts
INIT_ALL_41=$(docker exec nosh-db mysql -uroot -prootpassword nosh -N -B -e "SELECT COUNT(*) FROM allergies WHERE pid=41;" 2>/dev/null || echo "0")
INIT_ALL_43=$(docker exec nosh-db mysql -uroot -prootpassword nosh -N -B -e "SELECT COUNT(*) FROM allergies WHERE pid=43;" 2>/dev/null || echo "0")
INIT_ALL_45=$(docker exec nosh-db mysql -uroot -prootpassword nosh -N -B -e "SELECT COUNT(*) FROM allergies WHERE pid=45;" 2>/dev/null || echo "0")
INIT_ALL_46=$(docker exec nosh-db mysql -uroot -prootpassword nosh -N -B -e "SELECT COUNT(*) FROM allergies WHERE pid=46;" 2>/dev/null || echo "0")

# Encounter counts
INIT_ENC_41=$(docker exec nosh-db mysql -uroot -prootpassword nosh -N -B -e "SELECT COUNT(*) FROM encounters WHERE pid=41;" 2>/dev/null || echo "0")
INIT_ENC_42=$(docker exec nosh-db mysql -uroot -prootpassword nosh -N -B -e "SELECT COUNT(*) FROM encounters WHERE pid=42;" 2>/dev/null || echo "0")
INIT_ENC_43=$(docker exec nosh-db mysql -uroot -prootpassword nosh -N -B -e "SELECT COUNT(*) FROM encounters WHERE pid=43;" 2>/dev/null || echo "0")
INIT_ENC_44=$(docker exec nosh-db mysql -uroot -prootpassword nosh -N -B -e "SELECT COUNT(*) FROM encounters WHERE pid=44;" 2>/dev/null || echo "0")
INIT_ENC_45=$(docker exec nosh-db mysql -uroot -prootpassword nosh -N -B -e "SELECT COUNT(*) FROM encounters WHERE pid=45;" 2>/dev/null || echo "0")
INIT_ENC_46=$(docker exec nosh-db mysql -uroot -prootpassword nosh -N -B -e "SELECT COUNT(*) FROM encounters WHERE pid=46;" 2>/dev/null || echo "0")

# Schedule counts
INIT_SCH_41=$(docker exec nosh-db mysql -uroot -prootpassword nosh -N -B -e "SELECT COUNT(*) FROM schedule WHERE pid=41;" 2>/dev/null || echo "0")
INIT_SCH_44=$(docker exec nosh-db mysql -uroot -prootpassword nosh -N -B -e "SELECT COUNT(*) FROM schedule WHERE pid=44;" 2>/dev/null || echo "0")
INIT_SCH_45=$(docker exec nosh-db mysql -uroot -prootpassword nosh -N -B -e "SELECT COUNT(*) FROM schedule WHERE pid=45;" 2>/dev/null || echo "0")
INIT_SCH_46=$(docker exec nosh-db mysql -uroot -prootpassword nosh -N -B -e "SELECT COUNT(*) FROM schedule WHERE pid=46;" 2>/dev/null || echo "0")

# Write baseline files
echo "$INIT_ISS_41" > /tmp/${TASK_NAME}_init_iss41
echo "$INIT_ISS_42" > /tmp/${TASK_NAME}_init_iss42
echo "$INIT_ISS_43" > /tmp/${TASK_NAME}_init_iss43
echo "$INIT_ISS_44" > /tmp/${TASK_NAME}_init_iss44
echo "$INIT_ISS_45" > /tmp/${TASK_NAME}_init_iss45
echo "$INIT_ISS_46" > /tmp/${TASK_NAME}_init_iss46
echo "$INIT_RX_41"  > /tmp/${TASK_NAME}_init_rx41
echo "$INIT_RX_42"  > /tmp/${TASK_NAME}_init_rx42
echo "$INIT_RX_43"  > /tmp/${TASK_NAME}_init_rx43
echo "$INIT_RX_44"  > /tmp/${TASK_NAME}_init_rx44
echo "$INIT_RX_45"  > /tmp/${TASK_NAME}_init_rx45
echo "$INIT_RX_46"  > /tmp/${TASK_NAME}_init_rx46
echo "$INIT_ALL_41" > /tmp/${TASK_NAME}_init_all41
echo "$INIT_ALL_43" > /tmp/${TASK_NAME}_init_all43
echo "$INIT_ALL_45" > /tmp/${TASK_NAME}_init_all45
echo "$INIT_ALL_46" > /tmp/${TASK_NAME}_init_all46
echo "$INIT_ENC_41" > /tmp/${TASK_NAME}_init_enc41
echo "$INIT_ENC_42" > /tmp/${TASK_NAME}_init_enc42
echo "$INIT_ENC_43" > /tmp/${TASK_NAME}_init_enc43
echo "$INIT_ENC_44" > /tmp/${TASK_NAME}_init_enc44
echo "$INIT_ENC_45" > /tmp/${TASK_NAME}_init_enc45
echo "$INIT_ENC_46" > /tmp/${TASK_NAME}_init_enc46
echo "$INIT_SCH_41" > /tmp/${TASK_NAME}_init_sch41
echo "$INIT_SCH_44" > /tmp/${TASK_NAME}_init_sch44
echo "$INIT_SCH_45" > /tmp/${TASK_NAME}_init_sch45
echo "$INIT_SCH_46" > /tmp/${TASK_NAME}_init_sch46
date +%s > /tmp/${TASK_NAME}_start_ts

# ----------------------------------------------------------------
# 9. Launch Firefox to NOSH login page
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
echo "Quality review file placed at /home/ga/Desktop/quality_review.txt"
echo "Gap patients (agent must remediate):"
echo "  pid 41: Helen Mercer     — missing: E11.9 problem, Sulfonamide allergy, follow-up appt, encounter"
echo "  pid 42: Frank Costello    — missing: Losartan dose update 50->100mg, encounter"
echo "  pid 43: Beatrice Yamamoto — missing: M81.0 problem, Alendronate Rx, Iodine allergy, encounter"
echo "  pid 44: Raymond Delacroix — missing: K21.0 problem, Omeprazole Rx, follow-up appt, encounter"
echo "Noise (already complete - do NOT modify):"
echo "  pid 45: Dorothy Nguyen    — Hypertension + Amlodipine + Penicillin allergy + recent encounter"
echo "  pid 46: Walter Fitzgerald — COPD + Tiotropium + recent encounter"
