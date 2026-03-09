#!/usr/bin/env python3
"""Verifier for emergency_triage_workup task.

Priya Sharma (patient_p1_000015) must have all four emergency triage steps:
  1. Vitals recorded with ≥2 expected values          — 25 points
  2. Appendicitis/acute abdomen diagnosis added        — 25 points
  3. At least one lab order placed                     — 25 points
  4. At least one imaging order placed                 — 25 points

Pass threshold: 75 points (any 3 of 4 subtasks).
Wrong patient → 0.
"""
import json
import logging

logger = logging.getLogger(__name__)

EXPECTED_PATIENT_ID = "patient_p1_000015"
EXPECTED_VISIT_ID   = "visit_p1_000015"

VITALS_FIELDS      = ["weight", "height", "systolic", "diastolic", "heartrate", "heart_rate",
                      "temperature", "o2sat", "o2saturation", "spo2", "respiratoryrate"]
DIAGNOSIS_KEYWORDS = ["appendicitis", "appendix", "abdom", "acute", "peritonitis",
                      "rlq", "right lower", "right lower quadrant"]
LAB_KEYWORDS       = [
    "cbc", "complete blood", "differential", "crp", "c-reactive", "white blood",
    "wbc", "lab", "blood", "panel", "hematology", "biochemistry", "chemistry",
    "culture", "urine", "serum", "hemoglobin"
]
IMAGING_KEYWORDS   = [
    "ct", "computed tomography", "ultrasound", "sonogram", "abdomen", "pelvis",
    "imaging", "scan", "mri", "x-ray", "xray", "radiograph", "nuclear"
]
LAB_DOC_TYPES      = ["lab", "lab-request", "labrequest", "labs"]
IMAGING_DOC_TYPES  = ["imaging", "imaging-request", "imagingrequest"]
EXCLUDE_TYPES      = ["patient", "visit", "appointment"]
# Exclude the patient and visit base documents — they contain clinical keywords
# (e.g. "appendicitis" in reasonForVisit, "blood" in bloodType) and must not
# be counted as diagnosis/lab/imaging orders.
EXCLUDE_IDS        = {"patient_p1_000015", "visit_p1_000015"}


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


def _linked_to_sharma(doc):
    d       = doc.get("data", doc)
    doc_str = json.dumps(doc).lower()
    return (
        EXPECTED_PATIENT_ID in d.get("patient", "")
        or EXPECTED_PATIENT_ID in doc.get("patient", "")
        or EXPECTED_VISIT_ID  in d.get("visit", "")
        or EXPECTED_VISIT_ID  in doc.get("visit", "")
        or "sharma" in doc_str
        or "p00015" in doc_str
    )


def verify_emergency_triage_workup(traj, env_info, task_info):
    """
    Scoring (100 points total):
      - Vitals recorded for Priya Sharma (≥2 expected values) : 25 pts
      - Appendicitis/acute abdomen diagnosis                   : 25 pts
      - At least one lab order linked to Priya Sharma          : 25 pts
      - At least one imaging order linked to Priya Sharma      : 25 pts
    Pass threshold: 75 points (any 3 of 4 subtasks)
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
    subscores = {}

    # ── Subtask 1: Vitals ──────────────────────────────────────────────────────
    vitals_score = 0
    try:
        bp_sys  = metadata.get("bp_systolic", "110")
        bp_dia  = metadata.get("bp_diastolic", "72")
        hr      = metadata.get("heart_rate", "98")
        temp    = metadata.get("temperature", "38.2")
        weight  = metadata.get("weight_kg", "58")
        height  = metadata.get("height_cm", "165")

        for row in rows:
            doc    = row.get("doc", {})
            doc_id = row.get("id", "")
            if doc_id.startswith("_design"):
                continue
            if doc_id in EXCLUDE_IDS:
                continue
            if not _linked_to_sharma(doc):
                continue
            doc_str = json.dumps(doc).lower()
            d = doc.get("data", doc)
            doc_type = (d.get("type") or doc.get("type") or "").lower()
            if doc_type in EXCLUDE_TYPES:
                continue
            if not any(f in doc_str for f in VITALS_FIELDS):
                continue

            vals_found = sum(1 for v in [bp_sys, bp_dia, hr, temp, weight, height] if str(v) in doc_str)
            if vals_found >= 2:
                vitals_score = 25
                feedback_parts.append(f"Vitals recorded for Priya Sharma ({vals_found}/6 expected values)")
                break
            elif any(f in doc_str for f in VITALS_FIELDS):
                vitals_score = 15
                feedback_parts.append("Vitals doc found for Priya Sharma (expected values not confirmed)")

        if vitals_score == 0:
            feedback_parts.append("Vitals NOT recorded for Priya Sharma")
    except Exception as e:
        feedback_parts.append(f"Vitals check error: {e}")

    score += vitals_score
    subscores["vitals"] = vitals_score

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
            if not _linked_to_sharma(doc):
                continue
            d        = doc.get("data", doc)
            doc_str  = json.dumps(doc).lower()
            doc_type = (d.get("type") or doc.get("type") or "").lower()
            if doc_type in EXCLUDE_TYPES or doc_type in VITALS_FIELDS:
                continue
            if any(kw in doc_str for kw in DIAGNOSIS_KEYWORDS):
                matched = next(kw for kw in DIAGNOSIS_KEYWORDS if kw in doc_str)
                diagnosis_score = 25
                feedback_parts.append(f"Diagnosis containing '{matched}' found for Priya Sharma")
                break

        if diagnosis_score == 0:
            feedback_parts.append("Appendicitis/acute abdomen diagnosis NOT found for Priya Sharma")
    except Exception as e:
        feedback_parts.append(f"Diagnosis check error: {e}")

    score += diagnosis_score
    subscores["diagnosis"] = diagnosis_score

    # ── Subtask 3 + 4: Lab and Imaging orders ─────────────────────────────────
    lab_score     = 0
    imaging_score = 0

    try:
        for row in rows:
            doc    = row.get("doc", {})
            doc_id = row.get("id", "")
            if doc_id.startswith("_design"):
                continue
            if doc_id in EXCLUDE_IDS:
                continue
            if not _linked_to_sharma(doc):
                continue
            d        = doc.get("data", doc)
            doc_str  = json.dumps(doc).lower()
            doc_type = (d.get("type") or doc.get("type") or "").lower()

            if doc_type in ["patient", "visit", "appointment", "diagnosis"]:
                continue

            # Classify
            is_lab_type     = doc_type in LAB_DOC_TYPES
            is_imaging_type = doc_type in IMAGING_DOC_TYPES
            has_lab_kw      = any(kw in doc_str for kw in LAB_KEYWORDS)
            has_imaging_kw  = any(kw in doc_str for kw in IMAGING_KEYWORDS)

            if is_lab_type or (has_lab_kw and not is_imaging_type):
                if lab_score == 0:
                    lab_score = 25
                    feedback_parts.append("Lab order found for Priya Sharma")
            elif is_imaging_type or has_imaging_kw:
                if imaging_score == 0:
                    imaging_score = 25
                    feedback_parts.append("Imaging order found for Priya Sharma")

        if lab_score == 0:
            feedback_parts.append("No lab orders found for Priya Sharma")
        if imaging_score == 0:
            feedback_parts.append("No imaging orders found for Priya Sharma")

    except Exception as e:
        feedback_parts.append(f"Orders check error: {e}")

    score += lab_score + imaging_score
    subscores["lab_order"]     = lab_score
    subscores["imaging_order"] = imaging_score

    passed = score >= 75  # Requires 3 of 4 triage steps (vitals, diagnosis, plus at least one order)
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts) or "No triage steps completed",
        "subscores": subscores,
    }
