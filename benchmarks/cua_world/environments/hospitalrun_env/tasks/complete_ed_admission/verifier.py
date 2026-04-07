#!/usr/bin/env python3
"""Verifier for complete_ed_admission task.

David Nakamura must have a complete ED admission workflow:
  1. Patient registered (name match + demographics)       -- 17 pts
  2. Admission/emergency visit created                     -- 12 pts
  3. Vitals recorded (>=3 of 7 expected values)            -- 15 pts
  4. ACS/chest pain diagnosis added                        -- 12 pts
  5. Troponin lab order placed                             -- 12 pts
  6. Chest X-ray imaging order placed                      -- 12 pts
  7. Aspirin medication order placed                       -- 10 pts
  8. Cardiology follow-up appointment scheduled            -- 10 pts

Pass threshold: 50 points (at least ~5 of 8 subtasks).
"""
import json
import logging

logger = logging.getLogger(__name__)

VITALS_FIELDS = [
    "weight", "height", "systolic", "diastolic", "heartrate", "heart_rate",
    "temperature", "o2sat", "o2saturation", "spo2", "respiratoryrate",
    "respiratory_rate", "bloodpressure", "blood_pressure",
]
DIAGNOSIS_KEYWORDS = [
    "acute coronary", "coronary syndrome", "acs", "chest pain", "angina",
    "myocardial", "cardiac", "ami", "heart attack", "stemi", "nstemi",
]
LAB_KEYWORDS = [
    "troponin", "trop", "cardiac enzyme", "cardiac marker", "tnl", "tni",
]
IMAGING_KEYWORDS = [
    "x-ray", "xray", "chest", "radiograph", "cxr", "pa and lateral", "x ray",
]
MED_KEYWORDS = [
    "aspirin", "asa", "acetylsalicylic", "325",
]
APPT_KEYWORDS = [
    "cardiology", "cardiac", "cardiologist", "heart", "risk stratification",
    "post-ed",
]
VISIT_TYPE_KEYWORDS = [
    "admission", "admit", "emergency", "inpatient", "er ", "ed ",
]
EXCLUDE_DOC_TYPES = ["patient", "visit", "appointment"]
LAB_DOC_TYPES = ["lab", "lab-request", "labrequest", "labs"]
IMAGING_DOC_TYPES = ["imaging", "imaging-request", "imagingrequest"]
MED_DOC_TYPES = ["medication", "medication-request", "prescription"]


def _exec(exec_capture, cmd):
    try:
        return exec_capture(cmd)
    except Exception as e:
        logger.warning(f"exec_capture failed: {e}")
        return ""


def _load_all_docs(exec_capture):
    raw = _exec(
        exec_capture,
        "curl -s 'http://couchadmin:test@localhost:5984/main/_all_docs?include_docs=true'",
    )
    try:
        return json.loads(raw).get("rows", [])
    except Exception:
        return []


def _find_patient(rows):
    """Find the David Nakamura patient document. Returns (doc_id, doc) or (None, None)."""
    for row in rows:
        doc = row.get("doc", {})
        doc_id = row.get("id", "")
        if doc_id.startswith("_design"):
            continue
        d = doc.get("data", doc)
        first = d.get("firstName", "").lower()
        last = d.get("lastName", "").lower()
        if first == "david" and last == "nakamura":
            return doc_id, doc
    # Broader fallback
    for row in rows:
        doc = row.get("doc", {})
        doc_id = row.get("id", "")
        if doc_id.startswith("_design"):
            continue
        doc_str = json.dumps(doc).lower()
        if "nakamura" in doc_str and "david" in doc_str:
            d = doc.get("data", doc)
            if d.get("firstName") or d.get("lastName"):
                return doc_id, doc
    return None, None


def _linked_to_patient(doc, patient_doc_id):
    """Check if a document is linked to the patient."""
    d = doc.get("data", doc)
    doc_str = json.dumps(doc).lower()
    if patient_doc_id:
        if patient_doc_id in d.get("patient", ""):
            return True
        if patient_doc_id in doc.get("patient", ""):
            return True
    return "nakamura" in doc_str


def verify_complete_ed_admission(traj, env_info, task_info):
    """
    Scoring (100 points total):
      - Patient registered with correct name + demographics : 17 pts
      - Admission/emergency visit created                   : 12 pts
      - Vitals recorded (>=3 of 7 expected values)          : 15 pts
      - ACS/chest pain diagnosis added                      : 12 pts
      - Troponin lab order placed                           : 12 pts
      - Chest X-ray imaging order placed                    : 12 pts
      - Aspirin medication order placed                     : 10 pts
      - Cardiology follow-up appointment scheduled          : 10 pts
    Pass threshold: 50 points
    """
    exec_capture = env_info.get("exec_capture")
    metadata = task_info.get("metadata", {})

    if not exec_capture:
        return {
            "passed": False,
            "score": 0,
            "feedback": "exec_capture not available; cannot query CouchDB",
        }

    rows = _load_all_docs(exec_capture)
    if not rows:
        return {
            "passed": False,
            "score": 0,
            "feedback": "Could not reach CouchDB or no documents found",
        }

    score = 0
    feedback_parts = []
    subscores = {}

    # ── Subtask 1: Patient Registration ──────────────────────────────────────
    patient_score = 0
    patient_doc_id, patient_doc = _find_patient(rows)

    if patient_doc:
        patient_score = 12
        feedback_parts.append("Patient David Nakamura registered")

        # Check demographics for bonus points
        d = patient_doc.get("data", patient_doc)
        demo_checks = 0
        dob = d.get("dateOfBirth", "")
        if "1974" in dob:
            demo_checks += 1
        sex = d.get("sex", "").lower()
        if sex == "male" or sex == "m":
            demo_checks += 1
        blood = d.get("bloodType", "")
        if "a+" in blood.lower() or "a positive" in blood.lower():
            demo_checks += 1
        phone = d.get("phone", "")
        if "617" in phone and "0342" in phone:
            demo_checks += 1
        address = d.get("address", "").lower()
        if "elm" in address or "2847" in address or "boston" in address:
            demo_checks += 1

        if demo_checks >= 3:
            patient_score = 17
            feedback_parts.append(f"Demographics verified ({demo_checks}/5)")
        elif demo_checks >= 1:
            patient_score = 14
            feedback_parts.append(f"Partial demographics ({demo_checks}/5)")
    else:
        feedback_parts.append("Patient David Nakamura NOT found")

    score += patient_score
    subscores["patient_registration"] = patient_score

    # ── Subtask 2: Visit Created ─────────────────────────────────────────────
    visit_score = 0
    for row in rows:
        doc = row.get("doc", {})
        doc_id = row.get("id", "")
        if doc_id.startswith("_design"):
            continue
        if patient_doc_id and doc_id == patient_doc_id:
            continue
        if not _linked_to_patient(doc, patient_doc_id):
            continue
        d = doc.get("data", doc)
        doc_str = json.dumps(doc).lower()
        doc_type = (d.get("type") or doc.get("type") or "").lower()

        is_visit = (
            doc_type == "visit"
            or "visittype" in doc_str
            or "reasonforvisit" in doc_str
        )
        if not is_visit:
            continue

        has_visit_type = any(kw in doc_str for kw in VISIT_TYPE_KEYWORDS)
        has_location = "emergency" in doc_str
        if has_visit_type or has_location:
            visit_score = 12
            feedback_parts.append("Emergency/admission visit created")
            break
        else:
            visit_score = 8
            feedback_parts.append("Visit created (type/location not confirmed)")
            break

    if visit_score == 0:
        feedback_parts.append("No visit found for David Nakamura")

    score += visit_score
    subscores["visit"] = visit_score

    # ── Subtask 3: Vitals ────────────────────────────────────────────────────
    vitals_score = 0
    bp_sys = metadata.get("bp_systolic", "168")
    bp_dia = metadata.get("bp_diastolic", "98")
    hr = metadata.get("heart_rate", "104")
    rr = metadata.get("respiratory_rate", "22")
    temp = metadata.get("temperature", "37.2")
    o2 = metadata.get("o2_saturation", "95")
    weight = metadata.get("weight_kg", "91")
    height = metadata.get("height_cm", "175")

    for row in rows:
        doc = row.get("doc", {})
        doc_id = row.get("id", "")
        if doc_id.startswith("_design"):
            continue
        if patient_doc_id and doc_id == patient_doc_id:
            continue
        if not _linked_to_patient(doc, patient_doc_id):
            continue
        d = doc.get("data", doc)
        doc_str = json.dumps(doc).lower()
        doc_type = (d.get("type") or doc.get("type") or "").lower()
        if doc_type in ["patient", "visit", "appointment"]:
            continue
        if not any(f in doc_str for f in VITALS_FIELDS):
            continue

        expected = [bp_sys, bp_dia, hr, rr, temp, o2, weight, height]
        vals_found = sum(1 for v in expected if str(v) in doc_str)
        if vals_found >= 3:
            vitals_score = 15
            feedback_parts.append(
                f"Vitals recorded ({vals_found}/8 expected values)"
            )
            break
        elif vals_found >= 1 or any(f in doc_str for f in VITALS_FIELDS):
            vitals_score = 8
            feedback_parts.append("Vitals doc found (few expected values matched)")
            break

    if vitals_score == 0:
        feedback_parts.append("Vitals NOT recorded for David Nakamura")

    score += vitals_score
    subscores["vitals"] = vitals_score

    # ── Subtask 4: Diagnosis ─────────────────────────────────────────────────
    diagnosis_score = 0
    for row in rows:
        doc = row.get("doc", {})
        doc_id = row.get("id", "")
        if doc_id.startswith("_design"):
            continue
        if patient_doc_id and doc_id == patient_doc_id:
            continue
        if not _linked_to_patient(doc, patient_doc_id):
            continue
        d = doc.get("data", doc)
        doc_str = json.dumps(doc).lower()
        doc_type = (d.get("type") or doc.get("type") or "").lower()
        if doc_type in ["patient", "visit", "appointment", "vitals"]:
            continue
        if any(kw in doc_str for kw in DIAGNOSIS_KEYWORDS):
            matched = next(kw for kw in DIAGNOSIS_KEYWORDS if kw in doc_str)
            diagnosis_score = 12
            feedback_parts.append(
                f"Diagnosis containing '{matched}' found"
            )
            break

    if diagnosis_score == 0:
        feedback_parts.append("ACS/chest pain diagnosis NOT found")

    score += diagnosis_score
    subscores["diagnosis"] = diagnosis_score

    # ── Subtask 5 + 6: Lab and Imaging orders ────────────────────────────────
    lab_score = 0
    imaging_score = 0

    for row in rows:
        doc = row.get("doc", {})
        doc_id = row.get("id", "")
        if doc_id.startswith("_design"):
            continue
        if patient_doc_id and doc_id == patient_doc_id:
            continue
        if not _linked_to_patient(doc, patient_doc_id):
            continue
        d = doc.get("data", doc)
        doc_str = json.dumps(doc).lower()
        doc_type = (d.get("type") or doc.get("type") or "").lower()
        if doc_type in ["patient", "visit", "appointment", "vitals", "diagnosis"]:
            continue

        is_lab_type = doc_type in LAB_DOC_TYPES
        is_imaging_type = doc_type in IMAGING_DOC_TYPES
        has_lab_kw = any(kw in doc_str for kw in LAB_KEYWORDS)
        has_imaging_kw = any(kw in doc_str for kw in IMAGING_KEYWORDS)

        if lab_score == 0 and (is_lab_type or (has_lab_kw and not is_imaging_type)):
            lab_score = 12
            feedback_parts.append("Troponin lab order found")
        if imaging_score == 0 and (is_imaging_type or has_imaging_kw):
            imaging_score = 12
            feedback_parts.append("Chest X-ray imaging order found")

    if lab_score == 0:
        feedback_parts.append("No troponin lab order found")
    if imaging_score == 0:
        feedback_parts.append("No chest X-ray imaging order found")

    score += lab_score + imaging_score
    subscores["lab_order"] = lab_score
    subscores["imaging_order"] = imaging_score

    # ── Subtask 7: Medication ────────────────────────────────────────────────
    medication_score = 0
    for row in rows:
        doc = row.get("doc", {})
        doc_id = row.get("id", "")
        if doc_id.startswith("_design"):
            continue
        if patient_doc_id and doc_id == patient_doc_id:
            continue
        if not _linked_to_patient(doc, patient_doc_id):
            continue
        d = doc.get("data", doc)
        doc_str = json.dumps(doc).lower()
        doc_type = (d.get("type") or doc.get("type") or "").lower()
        if doc_type in ["patient", "visit", "appointment", "vitals", "diagnosis"]:
            continue

        is_med = (
            doc_type in MED_DOC_TYPES
            or any(kw in doc_str for kw in MED_KEYWORDS)
            or "medication" in doc_str
        )
        if is_med:
            medication_score = 10
            feedback_parts.append("Aspirin medication order found")
            break

    if medication_score == 0:
        feedback_parts.append("No aspirin medication order found")

    score += medication_score
    subscores["medication"] = medication_score

    # ── Subtask 8: Follow-up Appointment ─────────────────────────────────────
    appointment_score = 0
    for row in rows:
        doc = row.get("doc", {})
        doc_id = row.get("id", "")
        if doc_id.startswith("_design"):
            continue
        d = doc.get("data", doc)
        doc_str = json.dumps(doc).lower()

        # Check if it's an appointment with cardiology keywords
        reason = d.get("reasonForAppointment", d.get("reason", "")).lower()
        has_appt_kw = any(kw in reason for kw in APPT_KEYWORDS)
        if not has_appt_kw:
            has_appt_kw = any(kw in doc_str for kw in APPT_KEYWORDS)
        if not has_appt_kw:
            continue

        # Check if linked to Nakamura or is a cardiology appointment
        linked = _linked_to_patient(doc, patient_doc_id)
        if not linked and "nakamura" not in doc_str:
            # It's a cardiology appointment but may be linked via patient search
            patient_ref = d.get("patient", doc.get("patient", ""))
            if patient_doc_id and patient_doc_id not in patient_ref:
                continue

        # Check date range (April 1-14, 2026)
        start_date = d.get("startDate", d.get("date", "")).lower()
        has_april_date = (
            "2026-04" in start_date
            or "04/0" in start_date  # 04/01 through 04/09
            or "04/1" in start_date  # 04/10 through 04/14
            or "april" in doc_str
        )

        if has_april_date:
            appointment_score = 10
            feedback_parts.append("Cardiology follow-up appointment scheduled")
        else:
            appointment_score = 6
            feedback_parts.append(
                "Cardiology appointment found (date not in expected range)"
            )
        break

    if appointment_score == 0:
        feedback_parts.append("No cardiology follow-up appointment found")

    score += appointment_score
    subscores["appointment"] = appointment_score

    passed = score >= 50
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts) or "No ED admission steps completed",
        "subscores": subscores,
    }
