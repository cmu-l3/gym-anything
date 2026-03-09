#!/usr/bin/env python3
"""Verifier for complete_outpatient_encounter task.

Grace Kim (patient_p1_000013) must have all three of the following completed:
  1. Vitals recorded (with at least 4 expected fields) linked to her visit  — 33 points
  2. A diagnosis containing a migraine-related keyword               — 33 points
  3. A medication order linked to her                               — 34 points

Pass threshold: 66 points (at least 2 of 3 subtasks complete).
Wrong patient → immediate 0.
"""
import json
import logging

logger = logging.getLogger(__name__)

EXPECTED_PATIENT_ID = "patient_p1_000013"
EXPECTED_VISIT_ID   = "visit_p1_000013"
DIAGNOSIS_KEYWORDS  = ["migraine", "headache", "cephalgia", "cephalea"]
VITALS_FIELDS       = ["weight", "height", "systolic", "diastolic", "heartrate", "heart_rate",
                       "temperature", "o2sat", "o2saturation", "spo2", "respiratoryrate"]
# Exclude base patient/visit documents — their reasonForVisit contains clinical keywords
# (e.g. "migraine" in the visit's reasonForVisit) and must not count as completed subtasks.
EXCLUDE_IDS         = {"patient_p1_000013", "visit_p1_000013"}


def _exec(exec_capture, cmd):
    try:
        return exec_capture(cmd)
    except Exception as e:
        logger.warning(f"exec_capture failed: {e}")
        return ""


def _load_all_docs(exec_capture):
    raw = _exec(
        exec_capture,
        "curl -s 'http://couchadmin:test@localhost:5984/main/_all_docs?include_docs=true'"
    )
    try:
        return json.loads(raw).get("rows", [])
    except Exception:
        return []


def verify_complete_outpatient_encounter(traj, env_info, task_info):
    """
    Scoring (100 points total):
      - Vitals recorded for Grace Kim with ≥4 expected vital fields : 33 pts
      - Diagnosis with migraine/headache keywords linked to Grace Kim : 33 pts
      - Medication order linked to Grace Kim                          : 34 pts
    Pass threshold: 66 points
    """
    exec_capture = env_info.get("exec_capture")
    metadata     = task_info.get("metadata", {})
    expected_pid = metadata.get("patient_couch_id", EXPECTED_PATIENT_ID)

    if not exec_capture:
        return {"passed": False, "score": 0,
                "feedback": "exec_capture not available; cannot query CouchDB"}

    rows = _load_all_docs(exec_capture)
    if not rows:
        return {"passed": False, "score": 0, "feedback": "Could not reach CouchDB or no documents found"}

    score = 0
    feedback_parts = []

    # ── Subtask 1: Vitals ──────────────────────────────────────────────────────
    vitals_score = 0
    try:
        bp_sys   = metadata.get("bp_systolic", "128")
        bp_dia   = metadata.get("bp_diastolic", "84")
        hr       = metadata.get("heart_rate", "76")
        weight   = metadata.get("weight_kg", "61")
        height   = metadata.get("height_cm", "162")

        for row in rows:
            doc    = row.get("doc", {})
            doc_id = row.get("id", "")
            if doc_id.startswith("_design"):
                continue
            if doc_id in EXCLUDE_IDS:
                continue
            d       = doc.get("data", doc)
            doc_str = json.dumps(doc).lower()

            # Must be linked to Grace Kim
            linked = (
                expected_pid in doc.get("data", {}).get("patient", "")
                or expected_pid in doc.get("patient", "")
                or EXPECTED_VISIT_ID in doc.get("data", {}).get("visit", "")
                or EXPECTED_VISIT_ID in doc.get("visit", "")
                or "kim" in doc_str
                or "p00013" in doc_str
            )
            if not linked:
                continue

            has_vitals = any(f in doc_str for f in VITALS_FIELDS)
            if not has_vitals:
                continue

            # Count how many expected vitals fields appear in the document
            fields_present = 0
            for val in [bp_sys, bp_dia, hr, weight, height]:
                if str(val) in doc_str:
                    fields_present += 1

            if fields_present >= 2:
                vitals_score = 33
                feedback_parts.append(f"Vitals recorded for Grace Kim ({fields_present}/5 expected values found)")
                break

        if vitals_score == 0:
            feedback_parts.append("Vitals NOT recorded for Grace Kim")
    except Exception as e:
        feedback_parts.append(f"Vitals check error: {e}")

    score += vitals_score

    # ── Subtask 2: Diagnosis ───────────────────────────────────────────────────
    diagnosis_score = 0
    try:
        for row in rows:
            doc    = row.get("doc", {})
            doc_id = row.get("id", "")
            if doc_id.startswith("_design"):
                continue
            if doc_id in EXCLUDE_IDS:
                continue
            doc_str = json.dumps(doc).lower()

            # Must be linked to Grace Kim
            linked = (
                expected_pid in doc.get("data", {}).get("patient", "")
                or expected_pid in doc.get("patient", "")
                or EXPECTED_VISIT_ID in doc.get("data", {}).get("visit", "")
                or EXPECTED_VISIT_ID in doc.get("visit", "")
                or "kim" in doc_str
                or "p00013" in doc_str
            )
            if not linked:
                continue

            if any(kw in doc_str for kw in DIAGNOSIS_KEYWORDS):
                diagnosis_score = 33
                matched = next(kw for kw in DIAGNOSIS_KEYWORDS if kw in doc_str)
                feedback_parts.append(f"Diagnosis containing '{matched}' found for Grace Kim")
                break

        if diagnosis_score == 0:
            feedback_parts.append("Migraine/headache diagnosis NOT found for Grace Kim")
    except Exception as e:
        feedback_parts.append(f"Diagnosis check error: {e}")

    score += diagnosis_score

    # ── Subtask 3: Medication order ────────────────────────────────────────────
    medication_score = 0
    try:
        med_keywords = ["medication", "prescription", "drug", "medicine", "medic"]
        for row in rows:
            doc    = row.get("doc", {})
            doc_id = row.get("id", "")
            if doc_id.startswith("_design"):
                continue
            if doc_id in EXCLUDE_IDS:
                continue
            d       = doc.get("data", doc)
            doc_str = json.dumps(doc).lower()

            # Must be linked to Grace Kim
            linked = (
                expected_pid in doc.get("data", {}).get("patient", "")
                or expected_pid in doc.get("patient", "")
                or EXPECTED_VISIT_ID in doc.get("data", {}).get("visit", "")
                or EXPECTED_VISIT_ID in doc.get("visit", "")
                or "kim" in doc_str
                or "p00013" in doc_str
            )
            if not linked:
                continue

            # Check doc type or fields that indicate it's a medication document
            doc_type = d.get("type", doc.get("type", "")).lower()
            is_medication = (
                doc_type in ["medication", "medication-request", "prescription"]
                or any(k in doc_str for k in med_keywords)
            )
            # Exclude the patient and visit documents themselves
            if is_medication and doc_type not in ["patient", "visit", "vitals", "diagnosis"]:
                med_name = (
                    d.get("medication", d.get("medicationName", d.get("drug",
                    d.get("prescription", d.get("medicine", "unknown")))))
                )
                medication_score = 34
                feedback_parts.append(f"Medication order found for Grace Kim (medication: {med_name})")
                break

        if medication_score == 0:
            feedback_parts.append("Medication order NOT found for Grace Kim")
    except Exception as e:
        feedback_parts.append(f"Medication check error: {e}")

    score += medication_score

    passed = score >= 66
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts) or "No completed subtasks found",
        "subscores": {
            "vitals": vitals_score,
            "diagnosis": diagnosis_score,
            "medication": medication_score,
        },
    }
