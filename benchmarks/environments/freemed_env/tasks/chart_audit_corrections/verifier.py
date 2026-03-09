#!/usr/bin/env python3
"""
Verifier for chart_audit_corrections task.

Patients:
  - Malka Hartmann (ID 12, DOB 1994-11-26): phone 555-0-ERROR → 413-555-2847
  - Myrtis Armstrong (ID 16, DOB 1985-04-08): add Penicillin allergy (anaphylaxis/severe)
  - Arlie McClure (ID 17, DOB 1971-03-06): add ICD 250.00 (Type 2 Diabetes Mellitus)
Scoring (100 points):
  - Phone number corrected for Malka Hartmann: 30 pts
  - Penicillin allergy added for Myrtis Armstrong: 35 pts
  - Type 2 Diabetes diagnosis added for Arlie McClure: 35 pts
Pass threshold: >= 70 points
"""

import json
import tempfile
import os
import logging

logger = logging.getLogger(__name__)

CORRUPT_PHONE = "555-0-error"
CORRECT_PHONE_DIGITS = "4135552847"  # digits only for comparison
CORRECT_PHONE_AREA = "413"
CORRECT_PHONE_LAST4 = "2847"

EXPECTED_ALLERGEN = "penicillin"
EXPECTED_REACTION_TERMS = ["anaphylaxis", "anaphylac"]
EXPECTED_SEVERITY_TERMS = ["severe", "sev"]

EXPECTED_ICD_DM = "250"  # prefix match
EXPECTED_DM_TERMS = ["diabet", "250"]


def _digits_only(s: str) -> str:
    return "".join(c for c in s if c.isdigit())


def _in_str(value: str, terms: list) -> bool:
    vl = value.lower()
    return any(t in vl for t in terms)


def _icd_match(code: str, prefix: str) -> bool:
    c = code.strip().lower().replace(" ", "")
    p = prefix.strip().lower().replace(" ", "")
    return c == p or c.startswith(p) or p.startswith(c.rstrip(".0"))


def verify_chart_audit_corrections(traj, env_info, task_info):
    """Verify chart audit corrections across 3 patient records."""
    copy_from_env = env_info.get("copy_from_env")
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env unavailable"}

    try:
        with tempfile.NamedTemporaryFile(delete=False, suffix=".json") as tmp:
            tmp_path = tmp.name
        try:
            copy_from_env("/tmp/chart_audit_corrections_result.json", tmp_path)
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

    # ---- Criterion 1: Malka Hartmann phone corrected (30 pts) ----
    try:
        p12 = result.get("patient_12", {})
        p12_data = p12.get("data", {})
        current_phone = p12_data.get("phone", "")
        initial_phone = p12.get("initial_phone", "")

        phone_digits = _digits_only(current_phone)
        phone_changed = current_phone.lower() != initial_phone.lower()
        phone_not_corrupt = CORRUPT_PHONE not in current_phone.lower()
        area_ok = CORRECT_PHONE_AREA in current_phone
        last4_ok = CORRECT_PHONE_LAST4 in current_phone
        fully_correct = phone_digits == CORRECT_PHONE_DIGITS

        if fully_correct:
            score += 30
            subscores["phone_corrected"] = True
            feedback_parts.append(f"Malka Hartmann phone correctly updated to 413-555-2847 (30/30)")
        elif phone_changed and phone_not_corrupt and (area_ok or last4_ok):
            score += 18
            subscores["phone_corrected"] = "partial"
            feedback_parts.append(
                f"Malka Hartmann phone changed from corrupt value but not exactly right "
                f"(got: {current_phone!r}) (18/30)"
            )
        elif phone_changed and phone_not_corrupt:
            score += 10
            subscores["phone_corrected"] = "minimal"
            feedback_parts.append(
                f"Malka Hartmann phone changed but value incorrect (got: {current_phone!r}) (10/30)"
            )
        else:
            subscores["phone_corrected"] = False
            feedback_parts.append(
                f"Malka Hartmann phone NOT corrected (still: {current_phone!r}) (0/30)"
            )
    except Exception as e:
        subscores["phone_corrected"] = False
        feedback_parts.append(f"Phone check error: {e}")

    # ---- Criterion 2: Myrtis Armstrong Penicillin allergy added (35 pts) ----
    try:
        p16 = result.get("patient_16", {})
        allergies = p16.get("allergies", [])
        allergy_count = p16.get("allergy_count", 0)
        initial_allergy_count = p16.get("initial_allergy_count", 0)

        new_allergy_added = allergy_count > initial_allergy_count

        penicillin_entry = None
        for alg in allergies:
            if EXPECTED_ALLERGEN in alg.get("allergy", "").lower():
                penicillin_entry = alg
                break

        if penicillin_entry is None:
            subscores["penicillin_allergy"] = False
            feedback_parts.append("Myrtis Armstrong: Penicillin allergy NOT added (0/35)")
        else:
            reaction_ok = _in_str(penicillin_entry.get("reaction", ""), EXPECTED_REACTION_TERMS)
            severity_ok = _in_str(penicillin_entry.get("severity", ""), EXPECTED_SEVERITY_TERMS)
            detail_count = sum([reaction_ok, severity_ok])

            if detail_count >= 2:
                score += 35
                subscores["penicillin_allergy"] = True
                feedback_parts.append(
                    f"Myrtis Armstrong: Penicillin allergy added with full detail "
                    f"(reaction={penicillin_entry.get('reaction')}, "
                    f"severity={penicillin_entry.get('severity')}) (35/35)"
                )
            elif detail_count >= 1:
                score += 25
                subscores["penicillin_allergy"] = "partial"
                feedback_parts.append(
                    f"Myrtis Armstrong: Penicillin allergy added but partially incomplete "
                    f"(reaction={penicillin_entry.get('reaction')}, "
                    f"severity={penicillin_entry.get('severity')}) (25/35)"
                )
            else:
                score += 15
                subscores["penicillin_allergy"] = "minimal"
                feedback_parts.append(
                    f"Myrtis Armstrong: Penicillin allergy added but missing reaction/severity "
                    f"(reaction={penicillin_entry.get('reaction')}, "
                    f"severity={penicillin_entry.get('severity')}) (15/35)"
                )
    except Exception as e:
        subscores["penicillin_allergy"] = False
        feedback_parts.append(f"Allergy check error: {e}")

    # ---- Criterion 3: Arlie McClure diabetes diagnosis added (35 pts) ----
    try:
        p17 = result.get("patient_17", {})
        problem_codes = p17.get("problem_codes", [])
        problems = p17.get("problems", [])
        prob_count = p17.get("prob_count", 0)
        initial_prob_count = p17.get("initial_prob_count", 0)

        new_problem_added = prob_count > initial_prob_count

        dm_found = any(_icd_match(c, EXPECTED_ICD_DM) for c in problem_codes)
        # Also accept if diabetes appears in problem name text
        if not dm_found:
            dm_found = any(_in_str(p.get("name", ""), EXPECTED_DM_TERMS) for p in problems)

        if dm_found:
            # Check onset date if present
            dm_entry = next(
                (p for p in problems if _icd_match(p.get("code", ""), EXPECTED_ICD_DM)
                 or _in_str(p.get("name", ""), EXPECTED_DM_TERMS)),
                None
            )
            onset_ok = dm_entry and "2019" in dm_entry.get("onset", "")

            if onset_ok:
                score += 35
                subscores["diabetes_dx"] = True
                feedback_parts.append(
                    f"Arlie McClure: ICD 250.00 (Type 2 Diabetes) added with correct onset 2019-03-15 (35/35)"
                )
            else:
                score += 25
                subscores["diabetes_dx"] = "partial"
                onset_val = dm_entry.get("onset", "missing") if dm_entry else "missing"
                feedback_parts.append(
                    f"Arlie McClure: ICD 250.00 (Type 2 Diabetes) added but onset incorrect "
                    f"(got: {onset_val!r}, expected: 2019-03-15) (25/35)"
                )
        else:
            subscores["diabetes_dx"] = False
            feedback_parts.append(
                f"Arlie McClure: Type 2 Diabetes (ICD 250.00) NOT added to problem list "
                f"(codes found: {problem_codes}) (0/35)"
            )
    except Exception as e:
        subscores["diabetes_dx"] = False
        feedback_parts.append(f"Diagnosis check error: {e}")

    passed = score >= 70

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts) if feedback_parts else "No criteria evaluated",
        "subscores": subscores
    }
