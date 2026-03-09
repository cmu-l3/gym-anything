#!/usr/bin/env python3
"""Verifier for update_patient_and_schedule task.

Robert Kowalski (patient_p1_000006) must have:
  1. Phone updated to '617-555-0284'                              — 25 points
  2. Address updated (contains 'Oak Street', 'Boston', or '845') — 25 points
  3. New appointment with back pain reason within date range      — 50 points

Pass threshold: 50 points.
Wrong patient → 0.
"""
import json
import logging
from datetime import datetime

logger = logging.getLogger(__name__)

EXPECTED_PATIENT_ID  = "patient_p1_000006"
NEW_PHONE            = "617-555-0284"
ADDRESS_KEYWORDS     = ["oak street", "boston", "845"]
APPOINTMENT_KEYWORDS = ["back pain", "back", "follow-up", "followup", "follow up"]
APPT_START_AFTER     = datetime(2026, 3, 1)
APPT_START_BEFORE    = datetime(2026, 4, 30, 23, 59, 59)


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


def _parse_date(s):
    """Try common date formats used by HospitalRun."""
    for fmt in ("%m/%d/%Y", "%Y-%m-%d", "%d/%m/%Y"):
        try:
            return datetime.strptime(s.strip(), fmt)
        except (ValueError, AttributeError):
            pass
    return None


def verify_update_patient_and_schedule(traj, env_info, task_info):
    """
    Scoring (100 points):
      - Phone number updated to 617-555-0284 : 25 pts
      - Address updated with Boston/Oak Street : 25 pts
      - New back-pain appointment in date range : 50 pts
    Pass threshold: 50 points
    """
    exec_capture = env_info.get("exec_capture")
    metadata     = task_info.get("metadata", {})
    expected_pid = metadata.get("patient_couch_id", EXPECTED_PATIENT_ID)

    if not exec_capture:
        return {"passed": False, "score": 0,
                "feedback": "exec_capture not available; cannot query CouchDB"}

    score = 0
    feedback_parts = []
    subscores = {}

    # ── Fetch patient document directly ───────────────────────────────────────
    try:
        patient_raw = _exec(
            exec_capture,
            f"curl -s 'http://couchadmin:test@localhost:5984/main/{expected_pid}'"
        )
        patient_doc = json.loads(patient_raw) if patient_raw else {}
        d = patient_doc.get("data", patient_doc)

        # Subtask 1: Phone updated
        actual_phone = d.get("phone", patient_doc.get("phone", ""))
        if NEW_PHONE in actual_phone or actual_phone.replace("-", "").replace(" ", "") == NEW_PHONE.replace("-", ""):
            score += 25
            subscores["phone_updated"] = 25
            feedback_parts.append(f"Phone updated to '{actual_phone}'")
        else:
            subscores["phone_updated"] = 0
            feedback_parts.append(f"Phone NOT updated (current: '{actual_phone}', expected: '{NEW_PHONE}')")

        # Subtask 2: Address updated
        actual_addr = (d.get("address") or patient_doc.get("address") or "").lower()
        if any(kw in actual_addr for kw in ADDRESS_KEYWORDS):
            score += 25
            subscores["address_updated"] = 25
            feedback_parts.append(f"Address updated (contains expected keywords)")
        else:
            subscores["address_updated"] = 0
            feedback_parts.append(f"Address NOT updated (current: '{actual_addr}')")

    except Exception as e:
        subscores["phone_updated"] = 0
        subscores["address_updated"] = 0
        feedback_parts.append(f"Patient record check error: {e}")

    # ── Subtask 3: Appointment scheduled ─────────────────────────────────────
    appt_score = 0
    try:
        rows = _load_all_docs(exec_capture)
        for row in rows:
            doc    = row.get("doc", {})
            doc_id = row.get("id", "")
            if doc_id.startswith("_design") or doc_id == expected_pid:
                continue
            d       = doc.get("data", doc)
            doc_str = json.dumps(doc).lower()

            # Must be linked to Robert Kowalski
            patient_ref = d.get("patient", doc.get("patient", ""))
            if expected_pid not in patient_ref and "kowalski" not in doc_str and "p00006" not in doc_str:
                continue

            # Must be appointment-like
            doc_type = d.get("type", doc.get("type", "")).lower()
            is_appt = (
                doc_type == "appointment"
                or "startDate" in d or "start_date" in d
                or "appointmentType" in d or "appointment" in doc_str
            )
            if not is_appt:
                continue

            # Check reason
            reason = (d.get("reason") or doc.get("reason") or "").lower()
            if not any(kw in reason for kw in APPOINTMENT_KEYWORDS):
                continue

            # Check date range
            start_raw = d.get("startDate") or d.get("start_date") or d.get("startdate") or ""
            appt_dt = _parse_date(start_raw)
            if appt_dt is None:
                # Date not parseable but appointment found — give partial credit
                appt_score = 30
                feedback_parts.append(f"Back pain appointment found for Robert Kowalski (date unverified: '{start_raw}')")
                break

            if APPT_START_AFTER <= appt_dt <= APPT_START_BEFORE:
                appt_score = 50
                feedback_parts.append(
                    f"Back pain follow-up appointment scheduled for Robert Kowalski on {start_raw}"
                )
                break
            else:
                appt_score = 20
                feedback_parts.append(
                    f"Back pain appointment found but date '{start_raw}' outside expected range (03/01/2026–04/30/2026)"
                )

        if appt_score == 0:
            feedback_parts.append("No back pain follow-up appointment found for Robert Kowalski")

    except Exception as e:
        feedback_parts.append(f"Appointment check error: {e}")

    score += appt_score
    subscores["appointment"] = appt_score

    passed = score >= 50
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts) or "No updates detected",
        "subscores": subscores,
    }
