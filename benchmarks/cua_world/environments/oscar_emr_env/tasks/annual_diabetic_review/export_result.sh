#!/bin/bash
# Export script for Annual Diabetic Review task in OSCAR EMR

echo "=== Exporting Annual Diabetic Review Result ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_end_screenshot.png

PATIENT_NO=$(cat /tmp/task_patient_no_diabetic_review 2>/dev/null || oscar_query "SELECT demographic_no FROM demographic WHERE first_name='Fatima' AND last_name='Al-Hassan' LIMIT 1")
INITIAL_DRUG_COUNT=$(cat /tmp/initial_drug_count_dr 2>/dev/null || echo "4")
INITIAL_ALLERGY_COUNT=$(cat /tmp/initial_allergy_count_dr 2>/dev/null || echo "1")
INITIAL_MEASUREMENT_COUNT=$(cat /tmp/initial_measurement_count_dr 2>/dev/null || echo "0")
INITIAL_NOTE_COUNT=$(cat /tmp/initial_note_count_dr 2>/dev/null || echo "0")
INITIAL_TICKLER_COUNT=$(cat /tmp/initial_tickler_count_dr 2>/dev/null || echo "0")

echo "Patient demographic_no: $PATIENT_NO"

python3 << PYEOF
import json, subprocess
from datetime import datetime, timedelta

patient_no = "${PATIENT_NO}"
initial_drugs = int("${INITIAL_DRUG_COUNT}".strip() or "4")
initial_allergies = int("${INITIAL_ALLERGY_COUNT}".strip() or "1")
initial_measurements = int("${INITIAL_MEASUREMENT_COUNT}".strip() or "0")
initial_notes = int("${INITIAL_NOTE_COUNT}".strip() or "0")
initial_ticklers = int("${INITIAL_TICKLER_COUNT}".strip() or "0")

def run_query(q):
    try:
        r = subprocess.run(
            ['docker', 'exec', 'oscar-db', 'mysql', '-u', 'oscar', '-poscar', 'oscar', '-N', '-e', q],
            capture_output=True, text=True, timeout=15
        )
        return r.stdout.strip()
    except Exception:
        return ""

# ── Patient identity ──────────────────────────────────
patient_fname = run_query(f"SELECT first_name FROM demographic WHERE demographic_no={patient_no}")
patient_lname = run_query(f"SELECT last_name FROM demographic WHERE demographic_no={patient_no}")

# ── Measurements ──────────────────────────────────────
current_measurements = int(run_query(f"SELECT COUNT(*) FROM measurements WHERE demographicNo={patient_no}") or "0")
meas_rows = run_query(f"SELECT type, dataField FROM measurements WHERE demographicNo={patient_no} ORDER BY id DESC")

has_bp = False
has_wt = False
has_ht = False
has_hr = False
has_hba1c = False
has_glucose = False
all_meas = []

for line in meas_rows.splitlines():
    parts = line.split('\t')
    if len(parts) >= 2:
        mtype = parts[0].strip()
        mval = parts[1].strip()
        mtype_lower = mtype.lower()
        all_meas.append({'type': mtype, 'value': mval})

        if 'bp' in mtype_lower or 'blood' in mtype_lower and 'pressure' in mtype_lower:
            has_bp = True
        if '/' in mval:
            try:
                s, d = mval.split('/')
                s, d = int(s.strip()), int(d.strip())
                if 70 <= s <= 250 and 40 <= d <= 150:
                    has_bp = True
            except ValueError:
                pass
        if 'wt' in mtype_lower or 'weight' in mtype_lower:
            has_wt = True
        if 'ht' in mtype_lower or 'height' in mtype_lower:
            has_ht = True
        if 'hr' in mtype_lower or 'pulse' in mtype_lower or 'heart' in mtype_lower:
            has_hr = True
        if 'a1c' in mtype_lower or 'hba1c' in mtype_lower or 'hemoglobin' in mtype_lower:
            has_hba1c = True
        if 'glu' in mtype_lower or 'glucose' in mtype_lower or 'sugar' in mtype_lower or 'fbs' in mtype_lower or 'fasting' in mtype_lower:
            has_glucose = True

vitals_recorded = sum([has_bp, has_wt, has_ht, has_hr])
labs_recorded = sum([has_hba1c, has_glucose])

# ── Drugs: Glyburide status ──────────────────────────
glyburide_row = run_query(f"SELECT drugid, GN, archived FROM drugs WHERE demographic_no={patient_no} AND GN LIKE '%lyburide%' ORDER BY drugid DESC LIMIT 1")
glyburide_found = False
glyburide_archived = None
if glyburide_row:
    parts = glyburide_row.split('\t')
    glyburide_found = True
    glyburide_archived = parts[2].strip() == '1' if len(parts) > 2 else False

# ── Drugs: Sitagliptin status ────────────────────────
sitagliptin_row = run_query(f"SELECT drugid, GN, dosage, freqcode, archived FROM drugs WHERE demographic_no={patient_no} AND (GN LIKE '%itagliptin%' OR BN LIKE '%itagliptin%' OR GN LIKE '%Januvia%' OR BN LIKE '%Januvia%') ORDER BY drugid DESC LIMIT 1")
sitagliptin_found = False
sitagliptin_active = False
sitagliptin_dose_100mg = False
if sitagliptin_row:
    parts = sitagliptin_row.split('\t')
    sitagliptin_found = True
    dosage = parts[2].strip() if len(parts) > 2 else ''
    archived = parts[4].strip() if len(parts) > 4 else '1'
    sitagliptin_active = archived == '0'
    sitagliptin_dose_100mg = '100' in dosage

current_active_drugs = int(run_query(f"SELECT COUNT(*) FROM drugs WHERE demographic_no={patient_no} AND archived=0") or "0")

# All drugs summary
all_drugs_rows = run_query(f"SELECT GN, dosage, archived FROM drugs WHERE demographic_no={patient_no} ORDER BY drugid DESC")
drug_summary = []
for line in all_drugs_rows.splitlines():
    parts = line.split('\t')
    if len(parts) >= 3:
        drug_summary.append({'gn': parts[0], 'dosage': parts[1], 'archived': parts[2]})

# ── Allergies: Sulfonamide status ────────────────────
sulfa_row = run_query(f"SELECT allergyid, DESCRIPTION, reaction, severity_of_reaction, archived FROM allergies WHERE demographic_no={patient_no} AND (DESCRIPTION LIKE '%ulfonamid%' OR DESCRIPTION LIKE '%ulfa%') ORDER BY allergyid DESC LIMIT 1")
sulfa_allergy_found = False
sulfa_allergy_active = False
sulfa_severity_moderate = False
sulfa_reaction = ""
if sulfa_row:
    parts = sulfa_row.split('\t')
    sulfa_allergy_found = True
    archived = parts[4].strip() if len(parts) > 4 else '1'
    sulfa_allergy_active = archived == '0'
    sulfa_reaction = parts[2].strip() if len(parts) > 2 else ''
    severity = parts[3].strip().lower() if len(parts) > 3 else ''
    sulfa_severity_moderate = severity in ('2', 'mo', 'moderate') or 'moderate' in severity

current_active_allergies = int(run_query(f"SELECT COUNT(*) FROM allergies WHERE demographic_no={patient_no} AND archived=0") or "0")

# All allergies summary
all_allergies_rows = run_query(f"SELECT DESCRIPTION, reaction, severity_of_reaction, archived FROM allergies WHERE demographic_no={patient_no} ORDER BY allergyid DESC")
allergy_summary = []
for line in all_allergies_rows.splitlines():
    parts = line.split('\t')
    if len(parts) >= 1:
        allergy_summary.append({'desc': parts[0], 'reaction': parts[1] if len(parts)>1 else '', 'severity': parts[2] if len(parts)>2 else '', 'archived': parts[3] if len(parts)>3 else '?'})

# ── Encounter notes ──────────────────────────────────
current_notes = int(run_query(f"SELECT COUNT(*) FROM casemgmt_note WHERE demographic_no={patient_no}") or "0")
latest_note = run_query(f"SELECT LEFT(note, 1000) FROM casemgmt_note WHERE demographic_no={patient_no} ORDER BY note_id DESC LIMIT 1")

note_lower = latest_note.lower() if latest_note else ''
note_has_diabetic = any(kw in note_lower for kw in ['diabet', 'diabetes', 'diabetic'])
note_has_hba1c = any(kw in note_lower for kw in ['hba1c', 'a1c', 'hemoglobin a1c', '8.1'])
note_has_glyburide = any(kw in note_lower for kw in ['glyburide', 'diabeta', 'glibenclamide'])
note_has_sitagliptin = any(kw in note_lower for kw in ['sitagliptin', 'januvia'])
note_has_sulfonamide = any(kw in note_lower for kw in ['sulfonamid', 'sulfa'])
note_keyword_count = sum([note_has_diabetic, note_has_hba1c, note_has_glyburide, note_has_sitagliptin, note_has_sulfonamide])
note_has_content = len(latest_note.strip()) > 50 if latest_note else False

# ── Ticklers ─────────────────────────────────────────
current_ticklers = int(run_query(f"SELECT COUNT(*) FROM tickler WHERE demographic_no={patient_no}") or "0")
latest_tickler_msg = run_query(f"SELECT message FROM tickler WHERE demographic_no={patient_no} ORDER BY tickler_no DESC LIMIT 1")
latest_tickler_date = run_query(f"SELECT service_date FROM tickler WHERE demographic_no={patient_no} ORDER BY tickler_no DESC LIMIT 1")
latest_tickler_status = run_query(f"SELECT status FROM tickler WHERE demographic_no={patient_no} ORDER BY tickler_no DESC LIMIT 1")

tickler_lower = latest_tickler_msg.lower() if latest_tickler_msg else ''
tickler_has_diabetes = any(kw in tickler_lower for kw in ['diabet', 'diabetes'])
tickler_has_followup = any(kw in tickler_lower for kw in ['follow', 'a1c', 'hba1c', 'glucose'])
tickler_has_sitagliptin = 'sitagliptin' in tickler_lower or 'januvia' in tickler_lower
tickler_has_content = len(latest_tickler_msg.strip()) > 10 if latest_tickler_msg else False

# Check if tickler due date is approximately today + 90 days (within 7 day tolerance)
tickler_date_approx_correct = False
if latest_tickler_date:
    try:
        from datetime import date
        date_str = latest_tickler_date.strip().split(' ')[0]
        td = datetime.strptime(date_str, '%Y-%m-%d').date()
        expected = date.today() + timedelta(days=90)
        diff = abs((td - expected).days)
        tickler_date_approx_correct = diff <= 7
    except Exception:
        pass

result = {
    "patient_no": patient_no,
    "patient_fname": patient_fname,
    "patient_lname": patient_lname,
    # Baselines
    "initial_drug_count": initial_drugs,
    "initial_allergy_count": initial_allergies,
    "initial_measurement_count": initial_measurements,
    "initial_note_count": initial_notes,
    "initial_tickler_count": initial_ticklers,
    # Measurements
    "current_measurement_count": current_measurements,
    "new_measurement_count": current_measurements - initial_measurements,
    "has_bp": has_bp,
    "has_wt": has_wt,
    "has_ht": has_ht,
    "has_hr": has_hr,
    "has_hba1c": has_hba1c,
    "has_glucose": has_glucose,
    "vitals_recorded": vitals_recorded,
    "labs_recorded": labs_recorded,
    "all_measurements": all_meas[:20],
    # Drugs
    "current_active_drugs": current_active_drugs,
    "glyburide_found": glyburide_found,
    "glyburide_archived": glyburide_archived,
    "sitagliptin_found": sitagliptin_found,
    "sitagliptin_active": sitagliptin_active,
    "sitagliptin_dose_100mg": sitagliptin_dose_100mg,
    "drug_summary": drug_summary[:10],
    # Allergies
    "current_active_allergies": current_active_allergies,
    "sulfa_allergy_found": sulfa_allergy_found,
    "sulfa_allergy_active": sulfa_allergy_active,
    "sulfa_severity_moderate": sulfa_severity_moderate,
    "sulfa_reaction": sulfa_reaction,
    "allergy_summary": allergy_summary[:10],
    # Encounter notes
    "current_note_count": current_notes,
    "new_note_count": current_notes - initial_notes,
    "latest_note_excerpt": latest_note[:500] if latest_note else "",
    "note_has_content": note_has_content,
    "note_has_diabetic": note_has_diabetic,
    "note_has_hba1c": note_has_hba1c,
    "note_has_glyburide": note_has_glyburide,
    "note_has_sitagliptin": note_has_sitagliptin,
    "note_has_sulfonamide": note_has_sulfonamide,
    "note_keyword_count": note_keyword_count,
    # Ticklers
    "current_tickler_count": current_ticklers,
    "new_tickler_count": current_ticklers - initial_ticklers,
    "latest_tickler_message": latest_tickler_msg[:300] if latest_tickler_msg else "",
    "latest_tickler_date": latest_tickler_date,
    "latest_tickler_status": latest_tickler_status,
    "tickler_has_diabetes": tickler_has_diabetes,
    "tickler_has_followup": tickler_has_followup,
    "tickler_has_sitagliptin": tickler_has_sitagliptin,
    "tickler_has_content": tickler_has_content,
    "tickler_date_approx_correct": tickler_date_approx_correct,
    # Metadata
    "export_timestamp": datetime.now().isoformat()
}

with open('/tmp/annual_diabetic_review_result.json', 'w') as f:
    json.dump(result, f, indent=2)

print(f"Export: vitals={vitals_recorded}/4, labs={labs_recorded}/2")
print(f"        Glyburide found={glyburide_found}, archived={glyburide_archived}")
print(f"        Sitagliptin found={sitagliptin_found}, active={sitagliptin_active}, dose_100mg={sitagliptin_dose_100mg}")
print(f"        Sulfonamide allergy found={sulfa_allergy_found}, active={sulfa_allergy_active}")
print(f"        Notes: {current_notes - initial_notes} new, keywords={note_keyword_count}/5")
print(f"        Ticklers: {current_ticklers - initial_ticklers} new, date_ok={tickler_date_approx_correct}")
PYEOF

echo "Result saved to /tmp/annual_diabetic_review_result.json"
echo "=== Export Complete ==="
