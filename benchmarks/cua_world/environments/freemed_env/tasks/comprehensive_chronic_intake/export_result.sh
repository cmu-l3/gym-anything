#!/bin/bash
# Export results: comprehensive_chronic_intake
# New patient: Elena Vasquez-Moreno
# Uses ACTUAL FreeMED database column names verified against live schema

echo "=== Exporting comprehensive_chronic_intake results ==="

source /workspace/scripts/task_utils.sh

take_screenshot /tmp/comprehensive_chronic_intake_end.png

TASK_START=$(cat /tmp/task_start_timestamp 2>/dev/null || echo "0")
INITIAL_PATIENTS=$(cat /tmp/cci_initial_patients 2>/dev/null || echo "0")
INITIAL_INSCO=$(cat /tmp/cci_initial_insco 2>/dev/null || echo "0")

RESULT_FILE="/tmp/comprehensive_chronic_intake_result.json"

python3 << 'PYEOF'
import subprocess, json, os

TASK_START = int(open("/tmp/task_start_timestamp").read().strip() or "0")
INITIAL_PATIENTS = int(open("/tmp/cci_initial_patients").read().strip() or "0")
INITIAL_INSCO = int(open("/tmp/cci_initial_insco").read().strip() or "0")
RESULT_FILE = "/tmp/comprehensive_chronic_intake_result.json"

def q(sql):
    try:
        r = subprocess.run(
            ['mysql', '-u', 'freemed', '-pfreemed', 'freemed', '-N', '-B', '-e', sql],
            capture_output=True, text=True, timeout=30
        )
        return r.stdout.strip()
    except Exception:
        return ""

result = {
    "task_start": TASK_START,
    "initial_patients": INITIAL_PATIENTS,
    "initial_insco": INITIAL_INSCO,
}

# ===== Find patient Elena Vasquez =====
patient_raw = q("SELECT id, ptfname, ptlname, ptdob, ptsex, ptaddr1, ptcity, ptstate, ptzip, pthphone FROM patient WHERE ptfname LIKE '%Elena%' AND ptlname LIKE '%Vasquez%' LIMIT 1")

patient_found = bool(patient_raw.strip())
patient_data = {}
patient_id = None

if patient_raw.strip():
    parts = patient_raw.strip().split('\t')
    patient_id = int(parts[0]) if len(parts) > 0 and parts[0].strip() else None
    patient_data = {
        "id": patient_id,
        "fname": parts[1].strip() if len(parts) > 1 else "",
        "lname": parts[2].strip() if len(parts) > 2 else "",
        "dob": parts[3].strip() if len(parts) > 3 else "",
        "sex": parts[4].strip() if len(parts) > 4 else "",
        "addr": parts[5].strip() if len(parts) > 5 else "",
        "city": parts[6].strip() if len(parts) > 6 else "",
        "state": parts[7].strip() if len(parts) > 7 else "",
        "zip": parts[8].strip() if len(parts) > 8 else "",
        "phone": parts[9].strip() if len(parts) > 9 else "",
    }

result["patient_found"] = patient_found
result["patient_data"] = patient_data
result["patient_id"] = patient_id
result["current_patient_count"] = int(q("SELECT COUNT(*) FROM patient") or "0")

# ===== Insurance company (insco table) =====
insco_raw = q("SELECT id, insconame, inscoaddr1, inscocity, inscostate, inscozip, inscophone FROM insco WHERE insconame LIKE '%Northeastern Health%' LIMIT 1")
insco_found = bool(insco_raw.strip())
insco_data = {}
if insco_raw.strip():
    parts = insco_raw.strip().split('\t')
    insco_data = {
        "id": parts[0].strip() if len(parts) > 0 else "",
        "name": parts[1].strip() if len(parts) > 1 else "",
        "addr": parts[2].strip() if len(parts) > 2 else "",
        "city": parts[3].strip() if len(parts) > 3 else "",
        "state": parts[4].strip() if len(parts) > 4 else "",
        "zip": parts[5].strip() if len(parts) > 5 else "",
        "phone": parts[6].strip() if len(parts) > 6 else "",
    }
result["insco_found"] = insco_found
result["insco_data"] = insco_data
result["current_insco_count"] = int(q("SELECT COUNT(*) FROM insco") or "0")

# ===== Coverage (coverage table: covpatient, covinsco, covpatinsno, covpatgrpno, coveffdt, covplanname) =====
coverages = []
if patient_id:
    cov_raw = q(f"SELECT covinsco, covplanname, covpatinsno, covpatgrpno, coveffdt, covrel FROM coverage WHERE covpatient={patient_id}")
    if cov_raw.strip():
        for line in cov_raw.strip().split('\n'):
            parts = line.split('\t')
            coverages.append({
                "insco_id": parts[0].strip() if len(parts) > 0 else "",
                "plan": parts[1].strip() if len(parts) > 1 else "",
                "policy": parts[2].strip() if len(parts) > 2 else "",
                "group": parts[3].strip() if len(parts) > 3 else "",
                "effective": parts[4].strip() if len(parts) > 4 else "",
                "relationship": parts[5].strip() if len(parts) > 5 else "",
            })
result["coverages"] = coverages

# ===== Problem list (current_problems table: ppatient, problem, pdate) =====
# Note: FreeMED current_problems has no separate ICD code column; code is part of problem text
problems = []
if patient_id:
    probs_raw = q(f"SELECT problem, pdate FROM current_problems WHERE ppatient={patient_id}")
    if probs_raw.strip():
        for line in probs_raw.strip().split('\n'):
            parts = line.split('\t')
            problems.append({
                "problem": parts[0].strip() if len(parts) > 0 else "",
                "date": parts[1].strip() if len(parts) > 1 else "",
            })
result["problems"] = problems
result["problem_texts"] = [p["problem"] for p in problems]

# ===== Allergies (allergies_atomic table: allergy, reaction, severity, patient) =====
allergies = []
if patient_id:
    allergy_raw = q(f"SELECT allergy, reaction, severity FROM allergies_atomic WHERE patient={patient_id}")
    if allergy_raw.strip():
        for line in allergy_raw.strip().split('\n'):
            parts = line.split('\t')
            allergies.append({
                "allergy": parts[0].strip() if len(parts) > 0 else "",
                "reaction": parts[1].strip() if len(parts) > 1 else "",
                "severity": parts[2].strip() if len(parts) > 2 else "",
            })
result["allergies"] = allergies

# ===== Prescriptions (rx table: rxdrug, rxdosage, rxquantity, rxrefills, rxsig, rxpatient) =====
prescriptions = []
if patient_id:
    rx_raw = q(f"SELECT rxdrug, rxdosage, rxquantity, rxrefills, rxsig FROM rx WHERE rxpatient={patient_id}")
    if rx_raw.strip():
        for line in rx_raw.strip().split('\n'):
            parts = line.split('\t')
            prescriptions.append({
                "drug": parts[0].strip() if len(parts) > 0 else "",
                "dosage": parts[1].strip() if len(parts) > 1 else "",
                "quantity": parts[2].strip() if len(parts) > 2 else "",
                "refills": parts[3].strip() if len(parts) > 3 else "",
                "sig": parts[4].strip() if len(parts) > 4 else "",
            })
result["prescriptions"] = prescriptions

# ===== Also check medications table (different from rx; tracks current med list) =====
medications = []
if patient_id:
    med_raw = q(f"SELECT mdrugs FROM medications WHERE mpatient={patient_id}")
    if med_raw.strip():
        for line in med_raw.strip().split('\n'):
            medications.append(line.strip())
result["medications"] = medications

# ===== Vital signs (vitals table: v_bp_s_value, v_bp_d_value, v_pulse_value, v_temp_value, v_w_value, v_h_value) =====
vitals = {}
if patient_id:
    vitals_raw = q(f"SELECT v_bp_s_value, v_bp_d_value, v_pulse_value, v_temp_value, v_w_value, v_h_value FROM vitals WHERE patient={patient_id} ORDER BY id DESC LIMIT 1")
    if vitals_raw.strip():
        parts = vitals_raw.strip().split('\t')
        vitals = {
            "bp_systolic": parts[0].strip() if len(parts) > 0 else "",
            "bp_diastolic": parts[1].strip() if len(parts) > 1 else "",
            "heart_rate": parts[2].strip() if len(parts) > 2 else "",
            "temperature": parts[3].strip() if len(parts) > 3 else "",
            "weight": parts[4].strip() if len(parts) > 4 else "",
            "height": parts[5].strip() if len(parts) > 5 else "",
        }
result["vitals"] = vitals

# ===== Clinical notes (pnotes table uses SOAP format: pnotes_S, pnotes_O, pnotes_A, pnotes_P, pnotes_I, pnotes_E, pnotes_R) =====
note_text = ""
note_date = ""
note_sections = {}
if patient_id:
    notes_raw = q(f"SELECT pnotesdt, pnotes_S, pnotes_O, pnotes_A, pnotes_P, pnotes_I, pnotes_E, pnotes_R, pnotesdescrip FROM pnotes WHERE pnotespat={patient_id} ORDER BY pnotesdt DESC LIMIT 1")
    if notes_raw.strip():
        parts = notes_raw.strip().split('\t')
        note_date = parts[0].strip() if len(parts) > 0 else ""
        note_sections = {
            "subjective": parts[1].strip() if len(parts) > 1 else "",
            "objective": parts[2].strip() if len(parts) > 2 else "",
            "assessment": parts[3].strip() if len(parts) > 3 else "",
            "plan": parts[4].strip() if len(parts) > 4 else "",
            "interventions": parts[5].strip() if len(parts) > 5 else "",
            "evaluation": parts[6].strip() if len(parts) > 6 else "",
            "response": parts[7].strip() if len(parts) > 7 else "",
            "description": parts[8].strip() if len(parts) > 8 else "",
        }
        # Combine all non-empty sections into one text block for keyword searching
        note_text = " ".join(v for v in note_sections.values() if v and v != "NULL")
result["note_text"] = note_text
result["note_date"] = note_date
result["note_sections"] = note_sections

# ===== Referrals (referrals table: refpatient, refprovdest, refdx, refreasons, refstamp) =====
referrals = []
if patient_id:
    ref_raw = q(f"SELECT refprovdest, refdx, refreasons, refstamp FROM referrals WHERE refpatient={patient_id}")
    if ref_raw.strip():
        for line in ref_raw.strip().split('\n'):
            parts = line.split('\t')
            # Look up the destination provider name
            prov_id = parts[0].strip() if len(parts) > 0 else ""
            prov_name = ""
            if prov_id and prov_id != "0":
                prov_name = q(f"SELECT CONCAT(userfname, ' ', userlname) FROM user WHERE id={prov_id}")
            referrals.append({
                "provider_id": prov_id,
                "provider_name": prov_name.strip(),
                "dx": parts[1].strip() if len(parts) > 1 else "",
                "reasons": parts[2].strip() if len(parts) > 2 else "",
                "stamp": parts[3].strip() if len(parts) > 3 else "",
            })
result["referrals"] = referrals

# ===== Appointments (scheduler table: caldateof, calhour, calminute, calduration, caltype, calpatient) =====
appointments = []
if patient_id:
    appt_raw = q(f"SELECT caldateof, calhour, calminute, calduration, caltype FROM scheduler WHERE calpatient={patient_id}")
    if appt_raw.strip():
        for line in appt_raw.strip().split('\n'):
            parts = line.split('\t')
            appointments.append({
                "date": parts[0].strip() if len(parts) > 0 else "",
                "hour": parts[1].strip() if len(parts) > 1 else "",
                "minute": parts[2].strip() if len(parts) > 2 else "",
                "duration": parts[3].strip() if len(parts) > 3 else "",
                "type": parts[4].strip() if len(parts) > 4 else "",
            })
result["appointments"] = appointments

# ===== Write result =====
with open(RESULT_FILE, "w") as f:
    json.dump(result, f, indent=2)

print("Export complete.")
print(f"  Patient found: {patient_found} (ID: {patient_id})")
print(f"  Insurance: {insco_found}")
print(f"  Coverages: {len(coverages)}")
print(f"  Problems: {[p['problem'] for p in problems]}")
print(f"  Allergies: {[a['allergy'] for a in allergies]}")
print(f"  Prescriptions (rx): {[p['drug'] for p in prescriptions]}")
print(f"  Medications: {medications}")
print(f"  Vitals: {bool(vitals)}")
print(f"  Note: {bool(note_text)}")
print(f"  Referrals: {len(referrals)}")
print(f"  Appointments: {len(appointments)}")
PYEOF

echo "=== Export complete ==="
