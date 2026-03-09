#!/usr/bin/env python3
"""
Verifier for complex_chronic_disease_visit task.

Patient: Dwight Dach (ID 6, DOB 1998-03-21)
Scoring (100 points):
  - Hypertension diagnosis (ICD 401.9) in problem list: 20 pts
  - Prediabetes diagnosis (ICD 790.29) in problem list: 20 pts
  - Vital signs recorded with correct values (±tolerance): 25 pts
  - Lisinopril 10mg prescription (correct dose/quantity/refills): 20 pts
  - Clinical note mentioning both hypertension and prediabetes/diabetes: 15 pts
Pass threshold: >= 70 points
"""

import json
import tempfile
import os
import logging

logger = logging.getLogger(__name__)

EXPECTED_PATIENT_ID = 6
EXPECTED_HTN_ICD = "401.9"
EXPECTED_DM_ICD = "790.29"
BP_SYS_EXPECTED = 142
BP_DIA_EXPECTED = 88
HR_EXPECTED = 82
TEMP_EXPECTED = 98.6
WEIGHT_EXPECTED = 198
HEIGHT_EXPECTED = 70
DRUG_EXPECTED = "lisinopril"
DOSE_EXPECTED = "10"  # flexible: "10mg", "10 mg"
QUANTITY_EXPECTED = 30
REFILLS_EXPECTED = 2


def _icd_match(code: str, expected: str) -> bool:
    """Match ICD codes with/without decimal."""
    c = code.strip().lower().replace(" ", "")
    e = expected.strip().lower().replace(" ", "")
    return c == e or c.startswith(e) or e.startswith(c)


def _drug_match(drug: str, expected: str) -> bool:
    return expected.lower() in drug.lower()


def _in_range(val, expected, tolerance):
    try:
        return abs(float(val) - float(expected)) <= tolerance
    except (TypeError, ValueError):
        return False


def verify_complex_chronic_disease_visit(traj, env_info, task_info):
    """
    Verify complex chronic disease visit documentation for Dwight Dach.
    """
    copy_from_env = env_info.get("copy_from_env")
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env unavailable"}

    try:
        with tempfile.NamedTemporaryFile(delete=False, suffix=".json") as tmp:
            tmp_path = tmp.name
        try:
            copy_from_env("/tmp/complex_chronic_disease_visit_result.json", tmp_path)
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

    problem_codes = result.get("problem_codes", [])

    # ---- Criterion 1: Hypertension diagnosis (20 pts) ----
    try:
        htn_found = any(_icd_match(c, EXPECTED_HTN_ICD) for c in problem_codes)
        if htn_found:
            score += 20
            subscores["hypertension_icd"] = True
            feedback_parts.append(f"Hypertension (ICD {EXPECTED_HTN_ICD}) added to problem list (20/20)")
        else:
            subscores["hypertension_icd"] = False
            feedback_parts.append(f"Hypertension (ICD {EXPECTED_HTN_ICD}) NOT found in problem list (0/20)")
    except Exception as e:
        subscores["hypertension_icd"] = False
        feedback_parts.append(f"Hypertension check error: {e}")

    # ---- Criterion 2: Prediabetes diagnosis (20 pts) ----
    try:
        dm_found = any(_icd_match(c, EXPECTED_DM_ICD) for c in problem_codes)
        if dm_found:
            score += 20
            subscores["prediabetes_icd"] = True
            feedback_parts.append(f"Prediabetes (ICD {EXPECTED_DM_ICD}) added to problem list (20/20)")
        else:
            subscores["prediabetes_icd"] = False
            feedback_parts.append(f"Prediabetes (ICD {EXPECTED_DM_ICD}) NOT found in problem list (0/20)")
    except Exception as e:
        subscores["prediabetes_icd"] = False
        feedback_parts.append(f"Prediabetes check error: {e}")

    # ---- Criterion 3: Vital signs (25 pts) ----
    try:
        vitals = result.get("vitals", {})
        vitals_count = result.get("vitals_count", 0)
        initial_vitals = result.get("initial_vitals", 0)
        vitals_entered = vitals_count > initial_vitals

        if not vitals_entered:
            subscores["vitals"] = False
            feedback_parts.append("No new vital signs recorded (0/25)")
        else:
            # Check each vital value with tolerance
            bp_sys_ok = _in_range(vitals.get("bp_systolic", 0), BP_SYS_EXPECTED, 5)
            bp_dia_ok = _in_range(vitals.get("bp_diastolic", 0), BP_DIA_EXPECTED, 5)
            hr_ok = _in_range(vitals.get("heart_rate", 0), HR_EXPECTED, 5)
            temp_ok = _in_range(vitals.get("temperature", 0), TEMP_EXPECTED, 0.5)
            weight_ok = _in_range(vitals.get("weight", 0), WEIGHT_EXPECTED, 5)
            height_ok = _in_range(vitals.get("height", 0), HEIGHT_EXPECTED, 2)

            vital_checks = [bp_sys_ok, bp_dia_ok, hr_ok, temp_ok, weight_ok, height_ok]
            correct_count = sum(vital_checks)

            if correct_count >= 5:
                score += 25
                subscores["vitals"] = True
                feedback_parts.append(f"Vitals recorded correctly ({correct_count}/6 in range) (25/25)")
            elif correct_count >= 3:
                score += 12
                subscores["vitals"] = "partial"
                feedback_parts.append(f"Vitals partially correct ({correct_count}/6 in range) (12/25)")
            else:
                subscores["vitals"] = False
                v = vitals
                feedback_parts.append(
                    f"Vitals recorded but values wrong ({correct_count}/6 in range): "
                    f"BP={v.get('bp_systolic',0)}/{v.get('bp_diastolic',0)}, "
                    f"HR={v.get('heart_rate',0)}, Temp={v.get('temperature',0)}, "
                    f"Wt={v.get('weight',0)}, Ht={v.get('height',0)} (0/25)"
                )
    except Exception as e:
        subscores["vitals"] = False
        feedback_parts.append(f"Vitals check error: {e}")

    # ---- Criterion 4: Lisinopril prescription (20 pts) ----
    try:
        medications = result.get("medications", [])
        meds_count = result.get("meds_count", 0)
        initial_meds = result.get("initial_meds", 0)
        new_med_added = meds_count > initial_meds

        lisinopril_med = None
        for med in medications:
            if _drug_match(med.get("drug", ""), DRUG_EXPECTED):
                lisinopril_med = med
                break

        if lisinopril_med is None:
            subscores["lisinopril_rx"] = False
            feedback_parts.append("Lisinopril prescription NOT found (0/20)")
        else:
            dose_ok = DOSE_EXPECTED in lisinopril_med.get("dose", "").replace(" ", "").lower()
            qty_ok = str(QUANTITY_EXPECTED) in str(lisinopril_med.get("quantity", ""))
            refills_ok = str(REFILLS_EXPECTED) in str(lisinopril_med.get("refills", ""))

            rx_checks = sum([dose_ok, qty_ok, refills_ok])
            if rx_checks >= 2:
                score += 20
                subscores["lisinopril_rx"] = True
                feedback_parts.append(f"Lisinopril prescription correct (dose={lisinopril_med.get('dose')}, qty={lisinopril_med.get('quantity')}, refills={lisinopril_med.get('refills')}) (20/20)")
            else:
                score += 10
                subscores["lisinopril_rx"] = "partial"
                feedback_parts.append(f"Lisinopril found but details partially wrong (dose={lisinopril_med.get('dose')}, qty={lisinopril_med.get('quantity')}, refills={lisinopril_med.get('refills')}) (10/20)")
    except Exception as e:
        subscores["lisinopril_rx"] = False
        feedback_parts.append(f"Prescription check error: {e}")

    # ---- Criterion 5: Clinical note with both conditions mentioned (15 pts) ----
    try:
        note_text = result.get("note_text", "").lower()
        notes_count = result.get("notes_count", 0)
        initial_notes = result.get("initial_notes", 0)
        new_note_added = notes_count > initial_notes

        htn_terms = ["hypertension", "htn", "high blood pressure", "401.9"]
        dm_terms = ["prediabetes", "pre-diabetes", "diabetes", "790.29", "glucose", "hba1c", "a1c"]

        has_htn_mention = any(t in note_text for t in htn_terms)
        has_dm_mention = any(t in note_text for t in dm_terms)

        if not new_note_added or not note_text:
            subscores["clinical_note"] = False
            feedback_parts.append("No clinical note written (0/15)")
        elif has_htn_mention and has_dm_mention:
            score += 15
            subscores["clinical_note"] = True
            feedback_parts.append("Clinical note mentions both hypertension and diabetes/prediabetes (15/15)")
        elif has_htn_mention or has_dm_mention:
            score += 7
            subscores["clinical_note"] = "partial"
            feedback_parts.append("Clinical note mentions only one condition (7/15)")
        else:
            score += 5
            subscores["clinical_note"] = "partial_content"
            feedback_parts.append("Clinical note exists but does not mention required conditions (5/15)")
    except Exception as e:
        subscores["clinical_note"] = False
        feedback_parts.append(f"Clinical note check error: {e}")

    passed = score >= 70

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts) if feedback_parts else "No criteria evaluated",
        "subscores": subscores
    }
