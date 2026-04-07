#!/usr/bin/env python3
"""Verifier for locum_physician_self_employment task.

Dr. Aisha Kamara — hospital physician (T4) plus locum income (T4A via T2125).
Large RRSP ($28,900), professional expenses ($8,615), Ontario, married.

Scoring (100 pts total, pass threshold 60):
  Criterion 1: File saved correctly (15 pts)
  Criterion 2: Timestamp valid (10 pts)
  Criterion 3: Taxpayer name present (10 pts)
  Criterion 4: T4 hospital employment income ($145,000) (15 pts)
  Criterion 5: T4A locum income ($48,000) on T2125 (15 pts)
  Criterion 6: RRSP contribution ($28,900) (10 pts)
  Criterion 7: Professional expenses or RPP present (10 pts)
  Criterion 8: Spouse income / married filing present (15 pts)
  25 pts reserved for VLM evaluation

Score cap: Both T4 and T4A income amounts required to pass.
"""

import json
import os
import tempfile


def verify_locum_physician_self_employment(traj, env_info, task_info):
    """Verify Dr. Aisha Kamara physician dual-income return."""
    score = 0
    feedback = []

    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "No copy_from_env helper"}

    try:
        with tempfile.NamedTemporaryFile(delete=False, suffix='.json') as f:
            temp_path = f.name
        copy_from_env("C:/Users/Docker/Desktop/physician_result.json", temp_path)
        with open(temp_path, 'r', encoding='utf-8-sig') as f:
            result = json.load(f)
        os.unlink(temp_path)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Could not read result: {e}"}

    # --- Criterion 1: File saved with correct name (15 pts) ---
    file_ok = result.get('file_exists') and result.get('file_size_bytes', 0) > 500
    if file_ok:
        score += 15
        feedback.append("Return file 'aisha_kamara.24t' saved")
    else:
        feedback.append("FAIL: Return file not found or too small")

    # --- Criterion 2: Timestamp valid (10 pts) ---
    if result.get('file_is_new'):
        score += 10
        feedback.append("File timestamp valid")
    else:
        feedback.append("FAIL: File timestamp invalid")

    # --- Criterion 3: Taxpayer name (10 pts) ---
    name_ok = result.get('contains_kamara') and result.get('contains_aisha')
    if name_ok:
        score += 10
        feedback.append("Taxpayer name (Aisha Kamara) found")
    elif result.get('contains_kamara') or result.get('contains_aisha'):
        score += 5
        feedback.append("Taxpayer name partially found")
    else:
        feedback.append("FAIL: Taxpayer name not found")

    # --- Criterion 4: T4 hospital income $145,000 (15 pts) ---
    hospital_ok = result.get('contains_145000', False)
    if hospital_ok:
        score += 15
        feedback.append("T4 Sunnybrook employment income $145,000 found")
    else:
        feedback.append("FAIL: T4 employment income $145,000 not found")

    # --- Criterion 5: T4A locum income $48,000 (15 pts) ---
    locum_ok = result.get('contains_48000', False)
    se_marker = result.get('contains_self_employ', False)
    if locum_ok:
        score += 15
        feedback.append("T4A locum income $48,000 found")
    elif se_marker:
        score += 7
        feedback.append("Self-employment/T2125 marker found but $48,000 not confirmed")
    else:
        feedback.append("FAIL: T4A locum income $48,000 not found")

    # --- Criterion 6: RRSP contribution $28,900 (10 pts) ---
    rrsp_ok = result.get('contains_28900', False)
    if rrsp_ok:
        score += 10
        feedback.append("RRSP contribution $28,900 found")
    else:
        feedback.append("FAIL: RRSP $28,900 not found")

    # --- Criterion 7: Professional expenses or RPP from T4 (10 pts) ---
    cpso_ok = result.get('contains_1675', False)
    cme_ok = result.get('contains_3200', False)
    total_expense_ok = result.get('contains_8615', False)
    rpp_ok = result.get('contains_12650', False)
    union_ok = result.get('contains_2100', False)
    if total_expense_ok or (cpso_ok and cme_ok):
        score += 10
        feedback.append("Professional business expenses found ($8,615 or components)")
    elif cpso_ok or cme_ok or rpp_ok:
        score += 5
        feedback.append("Partial professional expense data found")
    elif union_ok:
        score += 3
        feedback.append("Union dues found (partial credit)")
    else:
        feedback.append("FAIL: Professional expenses not found")

    # --- Criterion 8: Married filing with spouse income $38,400 (15 pts) ---
    spouse_ok = result.get('contains_38400', False)
    if spouse_ok:
        score += 15
        feedback.append("Spouse income $38,400 (Kweku Kamara) found")
    else:
        # Partial credit if just Ontario province confirmed
        ontario_ok = result.get('contains_ontario', False)
        if ontario_ok:
            score += 5
            feedback.append("Province Ontario found (spouse income not confirmed)")
        else:
            feedback.append("FAIL: Spouse income / province not found")

    # --- Score cap: both income sources required ---
    if not (hospital_ok and locum_ok):
        score = min(score, 55)
        feedback.append("SCORE CAP: Both T4 ($145k) and T4A ($48k) required to pass")

    return {
        "passed": score >= 60,
        "score": score,
        "feedback": " | ".join(feedback),
        "details": {"vlm_reserved": 25, "max_programmatic": 100},
        "subscores": {
            "file_saved": 15 if file_ok else 0,
            "timestamp": 10 if result.get('file_is_new') else 0,
            "name": 10 if name_ok else (5 if (result.get('contains_kamara') or result.get('contains_aisha')) else 0),
            "t4_employment": 15 if hospital_ok else 0,
            "t4a_locum": 15 if locum_ok else (7 if se_marker else 0),
            "rrsp": 10 if rrsp_ok else 0,
            "professional_expenses": 10 if (total_expense_ok or (cpso_ok and cme_ok)) else (5 if (cpso_ok or cme_ok or rpp_ok) else (3 if union_ok else 0)),
            "spouse_married": 15 if spouse_ok else (5 if result.get('contains_ontario') else 0),
            "vlm_evaluation": "pending"
        }
    }
