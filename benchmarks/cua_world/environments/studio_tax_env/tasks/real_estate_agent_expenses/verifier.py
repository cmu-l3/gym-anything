#!/usr/bin/env python3
"""Verifier for real_estate_agent_expenses task.

Rodrigo Espinoza — real estate agent, Alberta.
T4 base salary ($36,000) + T4A commissions ($87,500) via T2125.
Extensive business expenses: vehicle CCA ($6,217), marketing ($10,630),
professional dues ($6,770), home office, RRSP ($10,000), donation ($500).

Scoring (100 pts total, pass threshold 60):
  Criterion 1: File saved correctly (15 pts)
  Criterion 2: Timestamp valid (10 pts)
  Criterion 3: Taxpayer name present (10 pts)
  Criterion 4: T4 base salary $36,000 present (10 pts)
  Criterion 5: T4A commission income $87,500 present (15 pts)
  Criterion 6: Major business expenses present (marketing or vehicle) (15 pts)
  Criterion 7: RRSP $10,000 and/or donation $500 (10 pts)
  Criterion 8: Alberta province + common-law partner present (15 pts)
  25 pts reserved for VLM evaluation

Score cap: T4A commission income ($87,500) must be present to pass.
"""

import json
import os
import tempfile


def verify_real_estate_agent_expenses(traj, env_info, task_info):
    """Verify Rodrigo Espinoza real estate agent return (Alberta)."""
    score = 0
    feedback = []

    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "No copy_from_env helper"}

    try:
        with tempfile.NamedTemporaryFile(delete=False, suffix='.json') as f:
            temp_path = f.name
        copy_from_env("C:/Users/Docker/Desktop/realestate_result.json", temp_path)
        with open(temp_path, 'r', encoding='utf-8-sig') as f:
            result = json.load(f)
        os.unlink(temp_path)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Could not read result: {e}"}

    # --- Criterion 1: File saved with correct name (15 pts) ---
    file_ok = result.get('file_exists') and result.get('file_size_bytes', 0) > 500
    if file_ok:
        score += 15
        feedback.append("Return file 'rodrigo_espinoza.24t' saved")
    else:
        feedback.append("FAIL: Return file not found or too small")

    # --- Criterion 2: Timestamp valid (10 pts) ---
    if result.get('file_is_new'):
        score += 10
        feedback.append("File timestamp valid")
    else:
        feedback.append("FAIL: File timestamp invalid")

    # --- Criterion 3: Taxpayer name (10 pts) ---
    name_ok = result.get('contains_espinoza') and result.get('contains_rodrigo')
    if name_ok:
        score += 10
        feedback.append("Taxpayer name (Rodrigo Espinoza) found")
    elif result.get('contains_espinoza') or result.get('contains_rodrigo'):
        score += 5
        feedback.append("Taxpayer name partially found")
    else:
        feedback.append("FAIL: Taxpayer name not found")

    # --- Criterion 4: T4 base salary $36,000 (10 pts) ---
    t4_ok = result.get('contains_36000', False)
    if t4_ok:
        score += 10
        feedback.append("T4 base salary $36,000 found")
    else:
        feedback.append("FAIL: T4 salary $36,000 not found")

    # --- Criterion 5: T4A commission income $87,500 (15 pts) ---
    commission_ok = result.get('contains_87500', False)
    if commission_ok:
        score += 15
        feedback.append("T4A commission income $87,500 found")
    else:
        feedback.append("FAIL: T4A commissions $87,500 not found")

    # --- Criterion 6: Major business expenses (15 pts) ---
    marketing_ok = result.get('contains_10630', False)
    vehicle_ok = result.get('contains_8342', False)
    cca_ok = result.get('contains_6217', False)
    prof_fees_ok = result.get('contains_6770', False)
    total_expense_ok = result.get('contains_40478', False)
    net_income_ok = result.get('contains_47022', False)

    expense_pts = 0
    expense_notes = []
    if marketing_ok:
        expense_pts += 5
        expense_notes.append("marketing $10,630")
    if vehicle_ok:
        expense_pts += 5
        expense_notes.append("vehicle $8,342")
    if cca_ok:
        expense_pts += 3
        expense_notes.append("CCA $6,217")
    if prof_fees_ok:
        expense_pts += 2
        expense_notes.append("professional fees $6,770")
    if total_expense_ok or net_income_ok:
        expense_pts = max(expense_pts, 12)
        expense_notes.append("total/net figures")

    expense_pts = min(expense_pts, 15)
    score += expense_pts
    if expense_pts >= 10:
        feedback.append(f"Business expenses found: {', '.join(expense_notes)}")
    elif expense_pts > 0:
        feedback.append(f"Partial business expense data: {', '.join(expense_notes)}")
    else:
        feedback.append("FAIL: No business expense amounts found")

    # --- Criterion 7: RRSP and/or charitable donation (10 pts) ---
    rrsp_ok = result.get('contains_10000', False)
    donation_ok = result.get('contains_500', False)
    if rrsp_ok and donation_ok:
        score += 10
        feedback.append("RRSP $10,000 and donation $500 found")
    elif rrsp_ok:
        score += 7
        feedback.append("RRSP $10,000 found")
    elif donation_ok:
        score += 3
        feedback.append("Donation $500 found")
    else:
        feedback.append("FAIL: RRSP $10,000 and donation $500 not found")

    # --- Criterion 8: Alberta province + common-law partner (15 pts) ---
    ab_ok = result.get('contains_alberta', False)
    partner_ok = result.get('contains_common_law', False)
    if ab_ok and partner_ok:
        score += 15
        feedback.append("Alberta province and common-law partner (Isabella Morales) found")
    elif ab_ok:
        score += 8
        feedback.append("Alberta province found (common-law partner not confirmed)")
    elif partner_ok:
        score += 5
        feedback.append("Common-law partner found (Alberta province not confirmed)")
    else:
        feedback.append("FAIL: Alberta province and common-law partner not found")

    # --- Score cap: commission income required to pass ---
    if not commission_ok:
        score = min(score, 55)
        feedback.append("SCORE CAP: Commission income $87,500 required to pass")

    return {
        "passed": score >= 60,
        "score": score,
        "feedback": " | ".join(feedback),
        "details": {"vlm_reserved": 25, "max_programmatic": 100},
        "subscores": {
            "file_saved": 15 if file_ok else 0,
            "timestamp": 10 if result.get('file_is_new') else 0,
            "name": 10 if name_ok else (5 if (result.get('contains_espinoza') or result.get('contains_rodrigo')) else 0),
            "t4_salary": 10 if t4_ok else 0,
            "commission_income": 15 if commission_ok else 0,
            "business_expenses": expense_pts,
            "rrsp_donation": 10 if (rrsp_ok and donation_ok) else (7 if rrsp_ok else (3 if donation_ok else 0)),
            "province_partner": 15 if (ab_ok and partner_ok) else (8 if ab_ok else (5 if partner_ok else 0)),
            "vlm_evaluation": "pending"
        }
    }
