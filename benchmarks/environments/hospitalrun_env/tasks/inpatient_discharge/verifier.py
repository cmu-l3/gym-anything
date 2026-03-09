#!/usr/bin/env python3
"""Verifier for inpatient_discharge task.

Arthur Jensen (patient_p1_000014) must have all four discharge steps completed:
  1. Vitals recorded (with ≥2 expected values)       — 25 points
  2. COPD-related discharge diagnosis added            — 25 points
  3. Respiratory medication order created              — 25 points
  4. Visit checked out / status updated to discharged  — 25 points

Pass threshold: 50 points (at least 2 of 4 subtasks complete).
"""
import json
import logging

logger = logging.getLogger(__name__)

EXPECTED_PATIENT_ID = "patient_p1_000014"
EXPECTED_VISIT_ID   = "visit_p1_000014"
VITALS_FIELDS       = ["weight", "height", "systolic", "diastolic", "heartrate", "heart_rate",
                       "temperature", "o2sat", "o2saturation", "spo2", "respiratoryrate"]
DIAGNOSIS_KEYWORDS  = ["copd", "chronic obstructive", "pulmonary", "respiratory", "emphysema", "bronchitis"]
# Exclude base patient/visit documents — their reasonForVisit contains clinical keywords
# (e.g. "COPD" in the visit's reasonForVisit) and must not count as completed subtasks.
EXCLUDE_IDS         = {"patient_p1_000014", "visit_p1_000014"}
MED_KEYWORDS        = ["albuterol", "salbutamol", "ipratropium", "tiotropium", "fluticasone",
                       "budesonide", "formoterol", "salmeterol", "spiriva", "ventolin",
                       "advair", "symbicort", "bronchod", "inhaler", "corticosteroid"]
DISCHARGE_KEYWORDS  = ["discharged", "completed", "checkout", "checked out", "discharge"]


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


def _linked_to_jensen(doc):
    d       = doc.get("data", doc)
    doc_str = json.dumps(doc).lower()
    return (
        EXPECTED_PATIENT_ID in d.get("patient", "")
        or EXPECTED_PATIENT_ID in doc.get("patient", "")
        or EXPECTED_VISIT_ID  in d.get("visit", "")
        or EXPECTED_VISIT_ID  in doc.get("visit", "")
        or "jensen" in doc_str
        or "p00014" in doc_str
    )


def verify_inpatient_discharge(traj, env_info, task_info):
    """
    Scoring (100 points total):
      - Vitals recorded for Arthur Jensen : 25 pts
      - COPD/respiratory discharge diagnosis : 25 pts
      - Respiratory medication order : 25 pts
      - Visit status changed to discharged/completed : 25 pts
    Pass threshold: 50 points
    """
    exec_capture = env_info.get("exec_capture")
    metadata     = task_info.get("metadata", {})

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
        bp_sys  = metadata.get("bp_systolic", "132")
        bp_dia  = metadata.get("bp_diastolic", "78")
        hr      = metadata.get("heart_rate", "82")
        weight  = metadata.get("weight_kg", "74")
        height  = metadata.get("height_cm", "178")

        for row in rows:
            doc    = row.get("doc", {})
            doc_id = row.get("id", "")
            if doc_id.startswith("_design"):
                continue
            if doc_id in EXCLUDE_IDS:
                continue
            if not _linked_to_jensen(doc):
                continue
            doc_str = json.dumps(doc).lower()
            if not any(f in doc_str for f in VITALS_FIELDS):
                continue

            vals_found = sum(1 for v in [bp_sys, bp_dia, hr, weight, height] if str(v) in doc_str)
            if vals_found >= 2:
                vitals_score = 25
                feedback_parts.append(f"Vitals recorded for Arthur Jensen ({vals_found}/5 expected values)")
                break

        if vitals_score == 0:
            # Looser check: any vitals doc linked to patient
            for row in rows:
                doc    = row.get("doc", {})
                doc_id = row.get("id", "")
                if doc_id.startswith("_design"):
                    continue
                if doc_id in EXCLUDE_IDS:
                    continue
                if not _linked_to_jensen(doc):
                    continue
                doc_str = json.dumps(doc).lower()
                if any(f in doc_str for f in VITALS_FIELDS):
                    vitals_score = 15
                    feedback_parts.append("Vitals recorded for Arthur Jensen (expected values not confirmed)")
                    break

        if vitals_score == 0:
            feedback_parts.append("Vitals NOT recorded for Arthur Jensen")
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
            if not _linked_to_jensen(doc):
                continue
            doc_str = json.dumps(doc).lower()
            d = doc.get("data", doc)
            doc_type = d.get("type", doc.get("type", "")).lower()
            # Exclude patient/visit/vitals docs
            if doc_type in ["patient", "visit", "vitals"]:
                continue
            if any(kw in doc_str for kw in DIAGNOSIS_KEYWORDS):
                diagnosis_score = 25
                matched = next(kw for kw in DIAGNOSIS_KEYWORDS if kw in doc_str)
                feedback_parts.append(f"Diagnosis containing '{matched}' found for Arthur Jensen")
                break

        if diagnosis_score == 0:
            feedback_parts.append("COPD/respiratory diagnosis NOT found for Arthur Jensen")
    except Exception as e:
        feedback_parts.append(f"Diagnosis check error: {e}")

    score += diagnosis_score
    subscores["diagnosis"] = diagnosis_score

    # ── Subtask 3: Medication order ────────────────────────────────────────────
    medication_score = 0
    try:
        for row in rows:
            doc    = row.get("doc", {})
            doc_id = row.get("id", "")
            if doc_id.startswith("_design"):
                continue
            if doc_id in EXCLUDE_IDS:
                continue
            if not _linked_to_jensen(doc):
                continue
            d       = doc.get("data", doc)
            doc_str = json.dumps(doc).lower()
            doc_type = d.get("type", doc.get("type", "")).lower()
            if doc_type in ["patient", "visit", "vitals", "diagnosis"]:
                continue
            # Is it a medication doc?
            is_med = (
                doc_type in ["medication", "medication-request", "prescription"]
                or any(kw in doc_str for kw in MED_KEYWORDS)
                or "medication" in doc_str
            )
            if is_med:
                med_name = d.get("medication", d.get("medicationName", d.get("drug", "unknown")))
                medication_score = 25
                feedback_parts.append(f"Medication order found for Arthur Jensen ('{med_name}')")
                break

        if medication_score == 0:
            feedback_parts.append("Respiratory medication order NOT found for Arthur Jensen")
    except Exception as e:
        feedback_parts.append(f"Medication check error: {e}")

    score += medication_score
    subscores["medication"] = medication_score

    # ── Subtask 4: Discharge / checkout ───────────────────────────────────────
    discharge_score = 0
    try:
        visit_raw = _exec(
            exec_capture,
            f"curl -s 'http://couchadmin:test@localhost:5984/main/{EXPECTED_VISIT_ID}'"
        )
        visit_doc = json.loads(visit_raw) if visit_raw else {}
        d = visit_doc.get("data", visit_doc)
        visit_str = json.dumps(visit_doc).lower()

        # Check if visit has checkout date or status changed to discharged/completed
        has_checkout = (
            d.get("checkoutDate") or d.get("endDate")
            or d.get("checkout_date") or d.get("discharged")
        )
        status = (d.get("status") or visit_doc.get("status") or "").lower()
        status_discharged = any(kw in status for kw in DISCHARGE_KEYWORDS)
        any_discharge_keyword = any(kw in visit_str for kw in DISCHARGE_KEYWORDS)

        if status_discharged or (has_checkout and any_discharge_keyword):
            discharge_score = 25
            feedback_parts.append(f"Visit checked out/discharged (status: '{status}')")
        elif has_checkout:
            discharge_score = 15
            feedback_parts.append(f"Visit has checkout date set (status: '{status}')")
        else:
            feedback_parts.append(f"Visit NOT discharged/checked out (current status: '{status}')")
    except Exception as e:
        feedback_parts.append(f"Discharge check error: {e}")

    score += discharge_score
    subscores["discharge"] = discharge_score

    passed = score >= 50
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts) or "No discharge steps completed",
        "subscores": subscores,
    }
