#!/usr/bin/env python3
"""Verifier for emigrant_departure_tax_hbp task.

Julian Baptiste — Emigrated to France Sept 30, 2024.
Requires Date of Departure entry, T4 income, Deemed Disposition (Departure Tax) on Schedule 3,
HBP un-repaid collapse inclusion, and EXCLUSION of post-departure foreign income.

Scoring (100 pts total, pass threshold 70):
  Criterion 1: File Integrity & Timestamp (10 pts)
  Criterion 2: Taxpayer Identity (10 pts)
  Criterion 3: Date of Departure / Part-Year (20 pts) [CRITICAL]
  Criterion 4: T4 Employment Income $115,000 (15 pts)
  Criterion 5: Deemed Disposition Proceeds $135,000 (15 pts)
  Criterion 6: Deemed Disposition ACB $45,000 (10 pts)
  Criterion 7: HBP Emigration Inclusion $12,000 (15 pts)
  Criterion 8: Foreign Income Excluded (5 pts)

Score cap: If the Date of Departure (09-30) is not found, score is capped at 55.
Filing a full-year resident return for an emigrant is a catastrophic compliance failure.
"""

import json
import os
import tempfile


def verify_emigrant_departure_tax(traj, env_info, task_info):
    """Verify Julian Baptiste emigrant part-year return."""
    score = 0
    feedback = []

    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "No copy_from_env helper available."}

    # Fetch the exported JSON file from the environment
    try:
        with tempfile.NamedTemporaryFile(delete=False, suffix='.json') as f:
            temp_path = f.name
        copy_from_env("C:/Users/Docker/Desktop/emigrant_result.json", temp_path)
        with open(temp_path, 'r', encoding='utf-8-sig') as f:
            result = json.load(f)
        os.unlink(temp_path)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Could not read exported result: {e}"}

    # --- Criterion 1: File Integrity & Timestamp (10 pts) ---
    file_ok = result.get('file_exists') and result.get('file_size_bytes', 0) > 500
    file_new = result.get('file_is_new')
    
    if file_ok and file_new:
        score += 10
        feedback.append("File 'julian_baptiste.24t' saved during task.")
    elif file_ok:
        score += 5
        feedback.append("File exists but timestamp verification failed.")
    else:
        feedback.append("FAIL: Return file not found or empty.")

    # --- Criterion 2: Taxpayer Identity (10 pts) ---
    name_ok = result.get('contains_baptiste') and result.get('contains_julian')
    if name_ok:
        score += 10
        feedback.append("Taxpayer name (Julian Baptiste) found.")
    else:
        feedback.append("FAIL: Taxpayer name not completely found.")

    # --- Criterion 3: Date of Departure (20 pts) [CRITICAL] ---
    departure_ok = result.get('contains_departure', False)
    if departure_ok:
        score += 20
        feedback.append("CRITICAL: Date of Departure (09-30) found — part-year status activated.")
    else:
        feedback.append("FAIL (CRITICAL): Date of Departure missing. Return incorrectly filed as full-year resident.")

    # --- Criterion 4: T4 Employment Income $115,000 (15 pts) ---
    t4_ok = result.get('contains_115000', False)
    if t4_ok:
        score += 15
        feedback.append("T4 employment income $115,000 found.")
    else:
        feedback.append("FAIL: T4 employment income not found.")

    # --- Criterion 5: Deemed Disposition Proceeds $135,000 (15 pts) ---
    proceeds_ok = result.get('contains_135000', False)
    if proceeds_ok:
        score += 15
        feedback.append("Deemed disposition FMV proceeds $135,000 found.")
    else:
        feedback.append("FAIL: Deemed disposition proceeds $135,000 not found.")

    # --- Criterion 6: Deemed Disposition ACB $45,000 (10 pts) ---
    acb_ok = result.get('contains_45000', False)
    if acb_ok:
        score += 10
        feedback.append("Deemed disposition ACB $45,000 found.")
    else:
        feedback.append("FAIL: Deemed disposition ACB $45,000 not found.")

    # --- Criterion 7: HBP Emigration Inclusion $12,000 (15 pts) ---
    hbp_ok = result.get('contains_12000', False)
    if hbp_ok:
        score += 15
        feedback.append("HBP collapse inclusion $12,000 found.")
    else:
        feedback.append("FAIL: HBP income inclusion $12,000 not found.")

    # --- Criterion 8: Foreign Income Excluded (5 pts) ---
    # Agent should IGNORE the post-departure €15,000 / $22,500 CAD entirely.
    foreign_included = result.get('contains_22500') or result.get('contains_15000')
    if not foreign_included:
        score += 5
        feedback.append("Post-departure foreign income correctly excluded.")
    else:
        feedback.append("FAIL: Post-departure foreign income improperly included on Canadian return.")

    # --- Apply Cap for Critical Compliance Error ---
    if not departure_ok and score > 55:
        score = 55
        feedback.append("SCORE CAPPED AT 55: Missing part-year departure date is a critical compliance failure.")

    # --- Determine Pass/Fail ---
    passed = score >= 70

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback),
        "details": {
            "departure_detected": departure_ok,
            "foreign_income_excluded": not foreign_included
        }
    }