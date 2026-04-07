#!/bin/bash
set -e
echo "=== Setting up annual_wellness_specialist_followup task ==="

# ── Helper ────────────────────────────────────────────────────────────────────
run_sql() {
    docker exec nosh-db mysql -uroot -prootpassword nosh -e "$1"
}
run_sql_val() {
    docker exec nosh-db mysql -uroot -prootpassword nosh -N -e "$1" | tr -d '[:space:]'
}

# ── 1. Clean prior task artifacts ─────────────────────────────────────────────
echo "--- Cleaning prior data for pid=900 ---"

# Remove today's encounters, ROS, PE for this patient
run_sql "DELETE FROM encounters WHERE pid=900 AND encounter_DOS >= CURDATE();"
run_sql "DELETE FROM ros WHERE pid=900 AND ros_date >= CURDATE();"
run_sql "DELETE FROM pe  WHERE pid=900 AND pe_date >= CURDATE();"

# Remove today's orders for this patient
run_sql "DELETE FROM orders WHERE pid=900;" || true

# Remove ALL problem list entries for this patient (will reseed cleanly)
run_sql "DELETE FROM issues WHERE pid=900;"

# Remove any future appointments for this patient
run_sql "DELETE FROM schedule WHERE pid=900 AND start > UNIX_TIMESTAMP();" || true

# Clean medication state — remove ALL rx_list for pid=900 to reseed cleanly
run_sql "DELETE FROM rx_list WHERE pid=900;"

# ── 1b. Ensure patient Margaret Thompson exists (pid=900) ─────────────────────
echo "--- Ensuring patient Margaret Thompson exists ---"

EXISTING=$(run_sql_val "SELECT COUNT(*) FROM demographics WHERE pid=900")
if [ "$EXISTING" = "0" ] || [ -z "$EXISTING" ]; then
    echo "Creating patient Margaret Thompson (pid=900)..."
    docker exec -i nosh-db mysql -uroot -prootpassword nosh <<'SQLEOF'
INSERT INTO `demographics` (`pid`, `lastname`, `firstname`, `DOB`, `sex`, `address`, `city`, `state`, `zip`, `phone_home`, `active`, `date`, `email`)
VALUES (900, 'Thompson', 'Margaret', '1958-04-22', 'f', '45 Elm Street', 'Springfield', 'MA', '01103', '413-555-8822', 1, NOW(), 'mthompson@email.com')
ON DUPLICATE KEY UPDATE `lastname`='Thompson', `firstname`='Margaret';

INSERT IGNORE INTO `demographics_relate` (`pid`, `id`, `practice_id`)
VALUES (900, 2, 1);
SQLEOF
    echo "Patient created."
else
    echo "Patient Margaret Thompson already exists."
fi

# Fix sex field — NOSH expects single-char 'f'/'m', not 'Female'/'Male'
# (Synthea-generated patients may have full words, which crash set_patient)
run_sql "UPDATE demographics SET sex='f' WHERE pid=900 AND sex NOT IN ('f','m');"

# ── 2. Seed problem list ─────────────────────────────────────────────────────
echo "--- Seeding problem list for pid=900 ---"

# DELIBERATELY INCORRECT: Type 1 Diabetes instead of Type 2
# Agent must discover and correct this
run_sql "
INSERT INTO issues (pid, issue, issue_date_active, type)
VALUES (900, 'Type 1 Diabetes Mellitus (E10.9)', '2020-03-15', 'Problem List');
"

# These are correct and should remain untouched
run_sql "
INSERT INTO issues (pid, issue, issue_date_active, type)
VALUES (900, 'Essential Hypertension (I10)', '2019-06-10', 'Problem List');
"
run_sql "
INSERT INTO issues (pid, issue, issue_date_active, type)
VALUES (900, 'Hyperlipidemia (E78.5)', '2020-01-20', 'Problem List');
"

# ── 3. Seed active medications ───────────────────────────────────────────────
echo "--- Seeding medications for pid=900 ---"

# Metformin 500mg — agent should increase to 1000mg per consultation letter
run_sql "
INSERT INTO rx_list (pid, id, rxl_medication, rxl_dosage, rxl_dosage_unit, rxl_sig, rxl_route, rxl_quantity, rxl_refill, rxl_date_active, rxl_date_inactive)
VALUES (900, 2, 'Metformin', '500', 'mg', 'Take one tablet twice daily with meals', 'Oral', '60', '3', DATE_SUB(CURDATE(), INTERVAL 365 DAY), NULL);
"

# Lisinopril 10mg — should be retained (no interaction)
run_sql "
INSERT INTO rx_list (pid, id, rxl_medication, rxl_dosage, rxl_dosage_unit, rxl_sig, rxl_route, rxl_quantity, rxl_refill, rxl_date_active, rxl_date_inactive)
VALUES (900, 2, 'Lisinopril', '10', 'mg', 'Take one tablet by mouth daily', 'Oral', '30', '3', DATE_SUB(CURDATE(), INTERVAL 365 DAY), NULL);
"

# Atorvastatin 20mg — should be retained (no interaction)
run_sql "
INSERT INTO rx_list (pid, id, rxl_medication, rxl_dosage, rxl_dosage_unit, rxl_sig, rxl_route, rxl_quantity, rxl_refill, rxl_date_active, rxl_date_inactive)
VALUES (900, 2, 'Atorvastatin', '20', 'mg', 'Take one tablet at bedtime', 'Oral', '30', '3', DATE_SUB(CURDATE(), INTERVAL 365 DAY), NULL);
"

# Naproxen 500mg — NSAID that interacts with Clopidogrel (antiplatelet)
# Agent must independently discover this interaction and discontinue
run_sql "
INSERT INTO rx_list (pid, id, rxl_medication, rxl_dosage, rxl_dosage_unit, rxl_sig, rxl_route, rxl_quantity, rxl_refill, rxl_date_active, rxl_date_inactive)
VALUES (900, 2, 'Naproxen', '500', 'mg', 'Take one tablet twice daily with food for knee pain', 'Oral', '60', '2', DATE_SUB(CURDATE(), INTERVAL 90 DAY), NULL);
"

# Omeprazole 20mg — gastroprotective, beneficial with antiplatelet therapy
# Anti-gaming: agent should NOT discontinue this
run_sql "
INSERT INTO rx_list (pid, id, rxl_medication, rxl_dosage, rxl_dosage_unit, rxl_sig, rxl_route, rxl_quantity, rxl_refill, rxl_date_active, rxl_date_inactive)
VALUES (900, 2, 'Omeprazole', '20', 'mg', 'Take one capsule daily before breakfast', 'Oral', '30', '5', DATE_SUB(CURDATE(), INTERVAL 180 DAY), NULL);
"

# ── 4. Record baseline counts for anti-gaming ────────────────────────────────
echo "--- Recording baseline counts ---"

rm -f /tmp/awsf_start_time.txt /tmp/awsf_init_enc.txt /tmp/awsf_init_ros.txt /tmp/awsf_init_pe.txt /tmp/awsf_init_ord.txt /tmp/awsf_init_rx.txt 2>/dev/null || true
date '+%Y-%m-%d %H:%M:%S' > /tmp/awsf_start_time.txt
run_sql_val "SELECT COUNT(*) FROM encounters WHERE pid=900" > /tmp/awsf_init_enc.txt
run_sql_val "SELECT COUNT(*) FROM ros WHERE pid=900" > /tmp/awsf_init_ros.txt
run_sql_val "SELECT COUNT(*) FROM pe WHERE pid=900" > /tmp/awsf_init_pe.txt
run_sql_val "SELECT COUNT(*) FROM orders WHERE pid=900" > /tmp/awsf_init_ord.txt
run_sql_val "SELECT COUNT(*) FROM rx_list WHERE pid=900" > /tmp/awsf_init_rx.txt

# ── 5. Write consultation letter to Desktop ──────────────────────────────────
echo "--- Writing consultation letter to Desktop ---"

mkdir -p /home/ga/Desktop

cat > /home/ga/Desktop/consultation_letter.txt << 'LETTER'
CARDIOLOGY CONSULTATION FOLLOW-UP

Patient: Margaret Thompson
DOB: 04/22/1958
Consulting Physician: Dr. Anil Mehta, Cardiology
Date of Consultation: Recent

Assessment:
Patient has newly identified cardiovascular risk factors including
borderline exercise stress test findings. Recommending antiplatelet
therapy initiation and optimized glucose management per endocrinology
co-management recommendations.

MEDICATION RECOMMENDATIONS:
1. Increase Metformin from 500mg to 1000mg twice daily
2. Start Clopidogrel 75mg daily for cardiovascular risk reduction

MONITORING:
Order the following labs for 3-month follow-up:
- Hemoglobin A1c (HbA1c)
- Comprehensive Metabolic Panel (CMP)
- Lipid Panel

CLINICAL FINDINGS TO DOCUMENT IN ENCOUNTER:

HPI:
67-year-old female with Type 2 Diabetes, hypertension, and
hyperlipidemia presents for annual wellness visit. Reports bilateral
knee stiffness worse in mornings, lasting approximately 30 minutes,
improving with activity. Denies chest pain, shortness of breath,
syncope, or unintentional weight changes. Current medications
generally well-tolerated.

Review of Systems:
- Constitutional: No fever, no unintentional weight loss
- Eyes: Wears bifocals, last dilated eye exam over 8 months ago
- ENT: Denies hearing changes or sinus congestion
- Cardiovascular: Denies chest pain, palpitations, or leg swelling
- Respiratory: Denies cough or shortness of breath
- GI: Occasional reflux, managed with current medication
- GU: Denies urinary frequency or urgency
- Musculoskeletal: Bilateral knee stiffness as noted in HPI
- Neurological: Denies numbness, tingling, or weakness
- Psychiatric: Denies depression, anxiety, or sleep disturbance

Physical Exam:
- General: Well-appearing female, no acute distress
- HEENT: Normocephalic, atraumatic, oropharynx clear
- Cardiovascular: Regular rate and rhythm, no murmurs, rubs, or gallops
- Lungs: Clear to auscultation bilaterally, no wheezes or crackles
- Abdomen: Soft, non-tender, non-distended, normoactive bowel sounds
- Extremities: No peripheral edema, bilateral knee crepitus on
  range of motion testing
LETTER

chmod 644 /home/ga/Desktop/consultation_letter.txt
chown ga:ga /home/ga/Desktop/consultation_letter.txt

# ── 6. Restart Firefox at login page ─────────────────────────────────────────
echo "--- Launching Firefox ---"

pkill -9 -f firefox || true
rm -f /home/ga/.mozilla/firefox/*/lock /home/ga/.mozilla/firefox/*/.parentlock 2>/dev/null || true
sleep 2

# Detect snap vs native Firefox
if command -v snap &>/dev/null && snap list firefox &>/dev/null 2>&1; then
    FIREFOX_CMD="snap run firefox"
else
    FIREFOX_CMD="firefox"
fi

su - ga -c "DISPLAY=:1 $FIREFOX_CMD --no-remote 'http://localhost/login' &" || \
su - ga -c "DISPLAY=:1 firefox --no-remote 'http://localhost/login' &"
sleep 8

# Maximize browser window
DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true

# Wait for Firefox to be detected by wmctrl (up to 20 seconds)
for i in $(seq 1 20); do
    if DISPLAY=:1 wmctrl -l 2>/dev/null | grep -qi "firefox\|mozilla\|nosh\|login"; then
        DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
        echo "Firefox window detected and maximized."
        break
    fi
    sleep 1
done

echo "=== annual_wellness_specialist_followup task setup complete ==="
echo "Patient: Margaret Thompson (pid=900, DOB 1958-04-22)"
echo "Seeded: 5 active medications, 3 problem list entries (1 incorrect)"
echo "Desktop: consultation_letter.txt with cardiology recommendations"
echo "Login: demo_provider / Provider1234!"
