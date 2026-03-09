#!/usr/bin/env python3
"""
Verifier for preventive_care_protocol task.

Patient: Sherill Botsford (ID 10, DOB 1995-01-24)
Scoring (100 points):
  - Vital signs recorded with correct values (±tolerance): 20 pts
  - Tdap immunization (vaccine name + lot TDP2024-441 + Sanofi Pasteur): 20 pts
  - Influenza immunization (vaccine name + lot FLQ2025-112 + Seqirus): 20 pts
  - Clinical note mentioning vaccines and preventive exam components: 20 pts
  - Follow-up appointment scheduled for 2026-03-01: 20 pts
Pass threshold: >= 70 points
"""

import json
import tempfile
import os
import logging

logger = logging.getLogger(__name__)

EXPECTED_PATIENT_ID = 10
BP_SYS_EXPECTED = 118
BP_DIA_EXPECTED = 76
HR_EXPECTED = 68
TEMP_EXPECTED = 98.2
WEIGHT_EXPECTED = 145
HEIGHT_EXPECTED = 65

TDAP_NAMES = ["tdap", "td", "dtp", "dtap", "tetanus", "diphtheria", "pertussis"]
TDAP_LOT = "TDP2024-441"
TDAP_MANUF = "sanofi"

FLU_NAMES = ["influenza", "flu", "flucelvax", "fluzone", "flublok", "flumist"]
FLU_LOT = "FLQ2025-112"
FLU_MANUF = "seqirus"

FOLLOWUP_DATE = "2026-03-01"


def _in_range(val, expected, tolerance):
    try:
        return abs(float(val) - float(expected)) <= tolerance
    except (TypeError, ValueError):
        return False


def _vaccine_name_match(vaccine: str, terms: list) -> bool:
    vl = vaccine.lower()
    return any(t in vl for t in terms)


def verify_preventive_care_protocol(traj, env_info, task_info):
    """Verify preventive care protocol documentation for Sherill Botsford."""
    copy_from_env = env_info.get("copy_from_env")
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env unavailable"}

    try:
        with tempfile.NamedTemporaryFile(delete=False, suffix=".json") as tmp:
            tmp_path = tmp.name
        try:
            copy_from_env("/tmp/preventive_care_protocol_result.json", tmp_path)
            with open(tmp_path, "r", encoding="utf-8") as f:
                result = json.load(f)
        finally:
            if os.path.exists(tmp_path):
                os.unlink(tmp_path)
    except FileNotFoundError:
        return {"passed": False, "score": 0, "feedback": "Result file not found — agent did not complete the task"}
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Error reading result: {e}"}

    score = 0
    feedback_parts = []
    subscores = {}

    # ---- Criterion 1: Vital signs (20 pts) ----
    try:
        vitals = result.get("vitals", {})
        vitals_count = result.get("vitals_count", 0)
        initial_vitals = result.get("initial_vitals", 0)
        vitals_entered = vitals_count > initial_vitals

        if not vitals_entered:
            subscores["vitals"] = False
            feedback_parts.append("No new vital signs recorded (0/20)")
        else:
            checks = [
                _in_range(vitals.get("bp_systolic", 0), BP_SYS_EXPECTED, 5),
                _in_range(vitals.get("bp_diastolic", 0), BP_DIA_EXPECTED, 5),
                _in_range(vitals.get("heart_rate", 0), HR_EXPECTED, 5),
                _in_range(vitals.get("temperature", 0), TEMP_EXPECTED, 0.5),
                _in_range(vitals.get("weight", 0), WEIGHT_EXPECTED, 5),
                _in_range(vitals.get("height", 0), HEIGHT_EXPECTED, 2),
            ]
            correct = sum(checks)
            if correct >= 5:
                score += 20
                subscores["vitals"] = True
                feedback_parts.append(f"Vital signs correct ({correct}/6 in range) (20/20)")
            elif correct >= 3:
                score += 10
                subscores["vitals"] = "partial"
                feedback_parts.append(f"Vital signs partially correct ({correct}/6 in range) (10/20)")
            else:
                subscores["vitals"] = False
                feedback_parts.append(f"Vital signs wrong ({correct}/6 in range) (0/20)")
    except Exception as e:
        subscores["vitals"] = False
        feedback_parts.append(f"Vitals check error: {e}")

    # ---- Criterion 2: Tdap immunization (20 pts) ----
    try:
        immunizations = result.get("immunizations", [])
        immun_count = result.get("immun_count", 0)
        initial_immun = result.get("initial_immunizations", 0)
        new_immun = immun_count > initial_immun

        tdap_entry = None
        for imm in immunizations:
            if _vaccine_name_match(imm.get("vaccine", ""), TDAP_NAMES):
                tdap_entry = imm
                break

        if not new_immun or tdap_entry is None:
            subscores["tdap_immunization"] = False
            feedback_parts.append("Tdap immunization NOT recorded (0/20)")
        else:
            lot_ok = TDAP_LOT.lower() in tdap_entry.get("lot_number", "").lower()
            manuf_ok = TDAP_MANUF.lower() in tdap_entry.get("manufacturer", "").lower()
            date_ok = "2025" in tdap_entry.get("date", "") or "03-01" in tdap_entry.get("date", "") or "2025-03-01" in tdap_entry.get("date", "")

            checks_ok = sum([lot_ok, manuf_ok, date_ok])
            if checks_ok >= 2:
                score += 20
                subscores["tdap_immunization"] = True
                feedback_parts.append(f"Tdap immunization documented correctly (lot={tdap_entry.get('lot_number')}, manufacturer={tdap_entry.get('manufacturer')}) (20/20)")
            else:
                score += 10
                subscores["tdap_immunization"] = "partial"
                feedback_parts.append(f"Tdap found but details incomplete (lot_ok={lot_ok}, manuf_ok={manuf_ok}) (10/20)")
    except Exception as e:
        subscores["tdap_immunization"] = False
        feedback_parts.append(f"Tdap check error: {e}")

    # ---- Criterion 3: Influenza immunization (20 pts) ----
    try:
        flu_entry = None
        for imm in result.get("immunizations", []):
            if _vaccine_name_match(imm.get("vaccine", ""), FLU_NAMES):
                flu_entry = imm
                break

        new_immun2 = result.get("immun_count", 0) > result.get("initial_immunizations", 0)

        if not new_immun2 or flu_entry is None:
            subscores["flu_immunization"] = False
            feedback_parts.append("Influenza immunization NOT recorded (0/20)")
        else:
            lot_ok = FLU_LOT.lower() in flu_entry.get("lot_number", "").lower()
            manuf_ok = FLU_MANUF.lower() in flu_entry.get("manufacturer", "").lower()
            date_ok = "2025" in flu_entry.get("date", "") or "2025-10-15" in flu_entry.get("date", "")

            checks_ok = sum([lot_ok, manuf_ok, date_ok])
            if checks_ok >= 2:
                score += 20
                subscores["flu_immunization"] = True
                feedback_parts.append(f"Influenza immunization documented correctly (lot={flu_entry.get('lot_number')}, manufacturer={flu_entry.get('manufacturer')}) (20/20)")
            else:
                score += 10
                subscores["flu_immunization"] = "partial"
                feedback_parts.append(f"Influenza found but details incomplete (lot_ok={lot_ok}, manuf_ok={manuf_ok}) (10/20)")
    except Exception as e:
        subscores["flu_immunization"] = False
        feedback_parts.append(f"Influenza check error: {e}")

    # ---- Criterion 4: Clinical note (20 pts) ----
    try:
        note_text = result.get("note_text", "").lower()
        notes_count = result.get("notes_count", 0)
        initial_notes = result.get("initial_notes", 0)
        new_note = notes_count > initial_notes

        vaccine_terms = ["tdap", "td", "influenza", "flu", "vaccine", "immunization", "vaccination"]
        preventive_terms = ["preventive", "annual", "physical", "exam", "breast", "cardiovascular", "well"]

        has_vaccine_mention = any(t in note_text for t in vaccine_terms)
        has_preventive_mention = any(t in note_text for t in preventive_terms)

        if not new_note or not note_text:
            subscores["clinical_note"] = False
            feedback_parts.append("No clinical note written (0/20)")
        elif has_vaccine_mention and has_preventive_mention:
            score += 20
            subscores["clinical_note"] = True
            feedback_parts.append("Clinical note documents vaccines and preventive exam (20/20)")
        elif has_vaccine_mention or has_preventive_mention:
            score += 10
            subscores["clinical_note"] = "partial"
            feedback_parts.append("Clinical note partially complete — missing vaccine or preventive mentions (10/20)")
        else:
            score += 5
            subscores["clinical_note"] = "minimal"
            feedback_parts.append("Clinical note exists but lacks required content (5/20)")
    except Exception as e:
        subscores["clinical_note"] = False
        feedback_parts.append(f"Clinical note check error: {e}")

    # ---- Criterion 5: Follow-up appointment (20 pts) ----
    try:
        appointments = result.get("appointments", [])
        appt_count = result.get("appt_count", 0)
        initial_appts = result.get("initial_appointments", 0)
        new_appt = appt_count > initial_appts

        followup_found = False
        time_ok = False
        for appt in appointments:
            appt_date = appt.get("date", "")
            appt_time = appt.get("time", "")
            if FOLLOWUP_DATE in appt_date or "2026" in appt_date:
                followup_found = True
                # Accept 10:00 in various formats: "10:00", "1000", "10:00:00"
                time_ok = "10:00" in appt_time or "10:0" in appt_time or appt_time.startswith("10")
                break

        if not new_appt or not followup_found:
            subscores["followup_appointment"] = False
            feedback_parts.append(f"Follow-up appointment for {FOLLOWUP_DATE} NOT scheduled (0/20)")
        elif time_ok:
            score += 20
            subscores["followup_appointment"] = True
            feedback_parts.append(f"Follow-up appointment scheduled for 2026-03-01 at 10:00 AM (20/20)")
        else:
            score += 15
            subscores["followup_appointment"] = "partial"
            feedback_parts.append(f"Follow-up appointment for 2026-03-01 scheduled but time may be off (15/20)")
    except Exception as e:
        subscores["followup_appointment"] = False
        feedback_parts.append(f"Appointment check error: {e}")

    passed = score >= 70

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts) if feedback_parts else "No criteria evaluated",
        "subscores": subscores
    }
