#!/usr/bin/env python3
"""Verifier for newcomer_partial_year_return task.

Amara Osei-Mensah — newcomer (permanent resident), part-year resident 2024.
Arrived April 1, 2024. T4 from RBC ($52,800), RPP ($2,640), FHSA ($4,000),
T2202 tuition ($1,800), Ontario Trillium Benefit (rent $26,550), spouse $0 income.

Scoring (100 pts total, pass threshold 60):
  Criterion 1: File saved correctly (15 pts)
  Criterion 2: Timestamp valid (10 pts)
  Criterion 3: Taxpayer name present (10 pts)
  Criterion 4: T4 employment income $52,800 present (15 pts)
  Criterion 5: Part-year residency / arrival date entered (20 pts) — critical
  Criterion 6: FHSA contribution $4,000 present (10 pts)
  Criterion 7: Tuition credit $1,800 or rent $26,550 present (10 pts)
  Criterion 8: Spouse entered (Kwame with $0 income) (10 pts)
  25 pts reserved for VLM evaluation

Score cap: Part-year arrival date must be detected for any score > 55.
This is the most critical element — filing as full-year resident is wrong.
"""

import json
import os
import tempfile


def verify_newcomer_partial_year_return(traj, env_info, task_info):
    """Verify Amara Osei-Mensah newcomer part-year resident return."""
    score = 0
    feedback = []

    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "No copy_from_env helper"}

    try:
        with tempfile.NamedTemporaryFile(delete=False, suffix='.json') as f:
            temp_path = f.name
        copy_from_env("C:/Users/Docker/Desktop/newcomer_result.json", temp_path)
        with open(temp_path, 'r', encoding='utf-8-sig') as f:
            result = json.load(f)
        os.unlink(temp_path)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Could not read result: {e}"}

    # --- Criterion 1: File saved with correct name (15 pts) ---
    file_ok = result.get('file_exists') and result.get('file_size_bytes', 0) > 500
    if file_ok:
        score += 15
        feedback.append("Return file 'amara_osei_mensah.24t' saved")
    else:
        feedback.append("FAIL: Return file not found or too small")

    # --- Criterion 2: Timestamp valid (10 pts) ---
    if result.get('file_is_new'):
        score += 10
        feedback.append("File timestamp valid")
    else:
        feedback.append("FAIL: File timestamp invalid")

    # --- Criterion 3: Taxpayer name (10 pts) ---
    name_ok = (result.get('contains_osei') or result.get('contains_mensah')) and result.get('contains_amara')
    name_partial = result.get('contains_osei') or result.get('contains_mensah') or result.get('contains_amara')
    if name_ok:
        score += 10
        feedback.append("Taxpayer name (Amara Osei-Mensah) found")
    elif name_partial:
        score += 5
        feedback.append("Taxpayer name partially found")
    else:
        feedback.append("FAIL: Taxpayer name not found")

    # --- Criterion 4: T4 employment income $52,800 (15 pts) ---
    employment_ok = result.get('contains_52800', False)
    if employment_ok:
        score += 15
        feedback.append("T4 RBC employment income $52,800 found")
    else:
        feedback.append("FAIL: T4 income $52,800 not found")

    # --- Criterion 5: Part-year residency/arrival date (20 pts — most critical) ---
    # Check for arrival date in file or part-year marker
    arrival_ok = result.get('contains_arrival_date', False)
    part_year_ok = result.get('contains_part_year', False)
    if arrival_ok:
        score += 20
        feedback.append("CRITICAL: Arrival date (April 1, 2024) entered — part-year residency correct")
    elif part_year_ok:
        score += 10
        feedback.append("Part-year/residency marker found (arrival date not confirmed)")
    else:
        feedback.append("FAIL: Arrival date not found — may be filed as full-year resident (CRITICAL ERROR)")

    # --- Criterion 6: FHSA contribution $4,000 (10 pts) ---
    fhsa_ok = result.get('contains_4000', False)
    if fhsa_ok:
        score += 10
        feedback.append("FHSA contribution $4,000 found")
    else:
        feedback.append("FAIL: FHSA $4,000 not found")

    # --- Criterion 7: Tuition $1,800 or rent for OTB $26,550 (10 pts) ---
    tuition_ok = result.get('contains_1800', False)
    rent_ok = result.get('contains_26550', False)
    ontario_ok = result.get('contains_ontario', False)
    if tuition_ok and rent_ok:
        score += 10
        feedback.append("Tuition credit $1,800 and OTB rent $26,550 found")
    elif tuition_ok:
        score += 6
        feedback.append("Tuition credit $1,800 found")
    elif rent_ok:
        score += 6
        feedback.append("OTB rent $26,550 found")
    elif ontario_ok:
        score += 3
        feedback.append("Ontario province found (tuition/rent not confirmed)")
    else:
        feedback.append("FAIL: Tuition/rent/Ontario not found")

    # --- Criterion 8: Spouse entered with $0 Canadian income (10 pts) ---
    spouse_ok = result.get('contains_kwame', False)
    if spouse_ok:
        score += 10
        feedback.append("Spouse Kwame Osei-Mensah entered")
    else:
        # RPP deduction is a proxy for proper T4 data entry
        rpp_ok = result.get('contains_2640', False)
        if rpp_ok:
            score += 5
            feedback.append("RPP pension $2,640 found (spouse not confirmed)")
        else:
            feedback.append("FAIL: Spouse not entered (Kwame with $0 Canadian income)")

    # --- Score cap: arrival date is the most critical element ---
    # Filing as full-year resident when the taxpayer is a part-year resident is a CRITICAL ERROR
    if not arrival_ok and not part_year_ok:
        score = min(score, 45)
        feedback.append("SCORE CAP: Part-year residency handling is CRITICAL — arrival date required")

    return {
        "passed": score >= 60,
        "score": score,
        "feedback": " | ".join(feedback),
        "details": {"vlm_reserved": 25, "max_programmatic": 100,
                    "critical_note": "Part-year residency is the most important element"},
        "subscores": {
            "file_saved": 15 if file_ok else 0,
            "timestamp": 10 if result.get('file_is_new') else 0,
            "name": 10 if name_ok else (5 if name_partial else 0),
            "employment": 15 if employment_ok else 0,
            "part_year_residency": 20 if arrival_ok else (10 if part_year_ok else 0),
            "fhsa": 10 if fhsa_ok else 0,
            "tuition_rent": 10 if (tuition_ok and rent_ok) else (6 if (tuition_ok or rent_ok) else (3 if ontario_ok else 0)),
            "spouse": 10 if spouse_ok else (5 if result.get('contains_2640') else 0),
            "vlm_evaluation": "pending"
        }
    }
