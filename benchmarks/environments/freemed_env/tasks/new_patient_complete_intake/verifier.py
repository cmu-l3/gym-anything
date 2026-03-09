#!/usr/bin/env python3
"""
Verifier for new_patient_complete_intake task.

New patient: Helena Vasquez (DOB 1978-08-14, Female)
Scoring (100 points):
  - Patient registered with correct demographics: 25 pts
  - Two diagnoses in problem list (Type 2 DM + Hypertension): 25 pts
  - Metformin 1000mg prescription (qty 90, 5 refills): 25 pts
  - Sulfonamides allergy documented (moderate, rash): 25 pts
Pass threshold: >= 70 points
"""

import json
import tempfile
import os
import logging

logger = logging.getLogger(__name__)

EXPECTED_FNAME = "helena"
EXPECTED_LNAME = "vasquez"
EXPECTED_DOB = "1978-08-14"
EXPECTED_SEX_OPTIONS = ["f", "female", "w", "woman"]  # flexible
EXPECTED_CITY = "boston"
EXPECTED_STATE = "ma"
EXPECTED_PHONE = "617-555-3892"

EXPECTED_ICD_DM = "250"     # 250 or 250.0 or 250.00
EXPECTED_ICD_HTN = "401.9"

EXPECTED_DRUG = "metformin"
EXPECTED_DOSE = "1000"
EXPECTED_QTY = 90
EXPECTED_REFILLS = 5

EXPECTED_ALLERGEN_TERMS = ["sulfonam", "sulfa", "sulphonam"]
EXPECTED_REACTION_TERMS = ["rash", "skin"]
EXPECTED_SEVERITY_TERMS = ["moderate", "mod"]


def _icd_match(code: str, prefix: str) -> bool:
    c = code.strip().lower().replace(" ", "")
    p = prefix.strip().lower().replace(" ", "")
    return c == p or c.startswith(p) or p.startswith(c.rstrip(".0"))


def _in_str(value: str, terms: list) -> bool:
    vl = value.lower()
    return any(t in vl for t in terms)


def verify_new_patient_complete_intake(traj, env_info, task_info):
    """Verify new patient Helena Vasquez registration and clinical intake."""
    copy_from_env = env_info.get("copy_from_env")
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env unavailable"}

    try:
        with tempfile.NamedTemporaryFile(delete=False, suffix=".json") as tmp:
            tmp_path = tmp.name
        try:
            copy_from_env("/tmp/new_patient_complete_intake_result.json", tmp_path)
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

    patient_found = result.get("patient_found", False)
    patient_data = result.get("patient_data", {})
    patient_id = result.get("patient_id")

    # ---- GATE: Patient must be registered before any clinical data can be checked ----
    if not patient_found or not patient_id:
        return {
            "passed": False,
            "score": 0,
            "feedback": "Patient Helena Vasquez not found in database — registration failed"
        }

    # ---- GATE: Verify the registered patient is actually Helena Vasquez ----
    fname_match = EXPECTED_FNAME in patient_data.get("fname", "").lower()
    lname_match = EXPECTED_LNAME in patient_data.get("lname", "").lower()
    if not fname_match or not lname_match:
        got_name = f"{patient_data.get('fname', '')} {patient_data.get('lname', '')}".strip()
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Wrong patient registered — expected Helena Vasquez, got '{got_name}' (score=0)"
        }

    # ---- Criterion 1: Patient registration with correct demographics (25 pts) ----
    try:
        name_ok = (
            EXPECTED_FNAME in patient_data.get("fname", "").lower() and
            EXPECTED_LNAME in patient_data.get("lname", "").lower()
        )
        dob_ok = EXPECTED_DOB in patient_data.get("dob", "")
        sex_ok = any(s in patient_data.get("sex", "").lower() for s in EXPECTED_SEX_OPTIONS)
        city_ok = EXPECTED_CITY in patient_data.get("city", "").lower()
        state_ok = EXPECTED_STATE in patient_data.get("state", "").lower()
        phone_ok = (
            "617" in patient_data.get("phone", "") and
            "3892" in patient_data.get("phone", "")
        )

        demo_checks = [name_ok, dob_ok, sex_ok, city_ok, state_ok, phone_ok]
        correct = sum(demo_checks)

        if correct >= 5:
            score += 25
            subscores["registration"] = True
            feedback_parts.append(f"Patient registered with correct demographics ({correct}/6 fields) (25/25)")
        elif correct >= 3:
            score += 12
            subscores["registration"] = "partial"
            feedback_parts.append(f"Patient registered but some demographics missing ({correct}/6 fields) (12/25)")
        else:
            score += 5
            subscores["registration"] = "minimal"
            feedback_parts.append(f"Patient exists but demographics incomplete ({correct}/6 fields) (5/25)")
    except Exception as e:
        subscores["registration"] = False
        feedback_parts.append(f"Registration check error: {e}")

    # ---- Criterion 2: Two diagnoses (25 pts) ----
    try:
        problem_codes = result.get("problem_codes", [])

        dm_found = any(_icd_match(c, EXPECTED_ICD_DM) for c in problem_codes)
        htn_found = any(_icd_match(c, EXPECTED_ICD_HTN) for c in problem_codes)

        if dm_found and htn_found:
            score += 25
            subscores["diagnoses"] = True
            feedback_parts.append(f"Both diagnoses documented (DM ICD 250.00 + HTN ICD 401.9) (25/25)")
        elif dm_found or htn_found:
            score += 12
            subscores["diagnoses"] = "partial"
            found_which = "DM (250.00)" if dm_found else "HTN (401.9)"
            feedback_parts.append(f"Only one diagnosis found: {found_which} (12/25)")
        else:
            subscores["diagnoses"] = False
            feedback_parts.append(f"No expected diagnoses found (codes found: {problem_codes}) (0/25)")
    except Exception as e:
        subscores["diagnoses"] = False
        feedback_parts.append(f"Diagnoses check error: {e}")

    # ---- Criterion 3: Metformin prescription (25 pts) ----
    try:
        medications = result.get("medications", [])

        metformin_med = None
        for med in medications:
            if EXPECTED_DRUG in med.get("drug", "").lower():
                metformin_med = med
                break

        if metformin_med is None:
            subscores["metformin_rx"] = False
            feedback_parts.append("Metformin prescription NOT found (0/25)")
        else:
            dose_ok = EXPECTED_DOSE in metformin_med.get("dose", "").replace(" ", "")
            qty_ok = str(EXPECTED_QTY) in str(metformin_med.get("quantity", ""))
            refills_ok = str(EXPECTED_REFILLS) in str(metformin_med.get("refills", ""))

            rx_checks = sum([dose_ok, qty_ok, refills_ok])
            if rx_checks >= 2:
                score += 25
                subscores["metformin_rx"] = True
                feedback_parts.append(f"Metformin prescription correct (dose={metformin_med.get('dose')}, qty={metformin_med.get('quantity')}, refills={metformin_med.get('refills')}) (25/25)")
            else:
                score += 12
                subscores["metformin_rx"] = "partial"
                feedback_parts.append(f"Metformin found but details wrong (dose={metformin_med.get('dose')}, qty={metformin_med.get('quantity')}, refills={metformin_med.get('refills')}) (12/25)")
    except Exception as e:
        subscores["metformin_rx"] = False
        feedback_parts.append(f"Prescription check error: {e}")

    # ---- Criterion 4: Sulfonamides allergy (25 pts) ----
    try:
        allergies = result.get("allergies", [])

        sulfa_allergy = None
        for alg in allergies:
            if _in_str(alg.get("allergy", ""), EXPECTED_ALLERGEN_TERMS):
                sulfa_allergy = alg
                break

        if sulfa_allergy is None:
            subscores["sulfa_allergy"] = False
            feedback_parts.append("Sulfonamides allergy NOT documented (0/25)")
        else:
            reaction_ok = _in_str(sulfa_allergy.get("reaction", ""), EXPECTED_REACTION_TERMS)
            severity_ok = _in_str(sulfa_allergy.get("severity", ""), EXPECTED_SEVERITY_TERMS)

            allergy_checks = sum([reaction_ok, severity_ok])
            if allergy_checks >= 1:
                score += 25
                subscores["sulfa_allergy"] = True
                feedback_parts.append(f"Sulfonamides allergy documented (reaction={sulfa_allergy.get('reaction')}, severity={sulfa_allergy.get('severity')}) (25/25)")
            else:
                score += 12
                subscores["sulfa_allergy"] = "partial"
                feedback_parts.append(f"Sulfonamides allergy found but details incomplete (reaction={sulfa_allergy.get('reaction')}, severity={sulfa_allergy.get('severity')}) (12/25)")
    except Exception as e:
        subscores["sulfa_allergy"] = False
        feedback_parts.append(f"Allergy check error: {e}")

    passed = score >= 70

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts) if feedback_parts else "No criteria evaluated",
        "subscores": subscores
    }
