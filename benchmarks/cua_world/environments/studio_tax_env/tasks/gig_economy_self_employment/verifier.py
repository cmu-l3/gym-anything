#!/usr/bin/env python3
"""Verifier for gig_economy_self_employment task.

Dimitri Papadopoulos — Uber/DoorDash driver filing self-employment return via T2125.

Scoring (100 pts total, pass threshold 60):
  Criterion 1: File saved with correct name (15 pts)
  Criterion 2: File is newer than task start (10 pts)
  Criterion 3: Taxpayer name present (10 pts)
  Criterion 4: Uber T4A income present ($34,840) (15 pts)
  Criterion 5: DoorDash T4A income present ($12,180) (15 pts)
  Criterion 6: Combined business income ($47,020) or individual amounts (10 pts)
  Criterion 7: Business expense or CCA markers present (10 pts)
  Criterion 8: File not too small / data-rich return (15 pts — guards against stub)
  25 pts reserved for VLM evaluation

Score cap: criteria 4+5 must both pass (>= 30 pts from income criteria) to pass the task.
This prevents a return filed for wrong person from passing on name check alone.
"""

import json
import os
import tempfile


def verify_gig_economy_self_employment(traj, env_info, task_info):
    """Verify Dimitri Papadopoulos gig economy self-employment return."""
    score = 0
    feedback = []

    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "No copy_from_env helper"}

    try:
        with tempfile.NamedTemporaryFile(delete=False, suffix='.json') as f:
            temp_path = f.name
        copy_from_env("C:/Users/Docker/Desktop/gig_economy_result.json", temp_path)
        with open(temp_path, 'r', encoding='utf-8-sig') as f:
            result = json.load(f)
        os.unlink(temp_path)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Could not read result: {e}"}

    # --- Criterion 1: File saved with correct name (15 pts) ---
    file_ok = result.get('file_exists') and result.get('file_size_bytes', 0) > 500
    if file_ok:
        score += 15
        feedback.append("Return file 'dimitri_papadopoulos.24t' saved")
    else:
        feedback.append("FAIL: Return file not found or too small")

    # --- Criterion 2: Timestamp valid — file created/modified after task start (10 pts) ---
    if result.get('file_is_new'):
        score += 10
        feedback.append("File timestamp valid")
    else:
        feedback.append("FAIL: File timestamp invalid (pre-existing file?)")

    # --- Criterion 3: Taxpayer name present (10 pts) ---
    name_ok = result.get('contains_papadopoulos') and result.get('contains_dimitri')
    if name_ok:
        score += 10
        feedback.append("Taxpayer name (Dimitri Papadopoulos) found")
    elif result.get('contains_papadopoulos') or result.get('contains_dimitri'):
        score += 5
        feedback.append("Taxpayer name partially found")
    else:
        feedback.append("FAIL: Taxpayer name not found — wrong return filed?")

    # --- Criterion 4: Uber T4A income ($34,840) (15 pts) ---
    uber_ok = result.get('contains_34840', False)
    if uber_ok:
        score += 15
        feedback.append("Uber T4A income $34,840 found")
    else:
        feedback.append("FAIL: Uber income $34,840 not found")

    # --- Criterion 5: DoorDash T4A income ($12,180) (15 pts) ---
    doordash_ok = result.get('contains_12180', False)
    if doordash_ok:
        score += 15
        feedback.append("DoorDash T4A income $12,180 found")
    else:
        feedback.append("FAIL: DoorDash income $12,180 not found")

    # --- Criterion 6: Combined gross income ($47,020) or self-employment markers (10 pts) ---
    combined_ok = result.get('contains_47020', False)
    se_marker = result.get('contains_self_employ', False)
    net_income_ok = result.get('contains_35527', False)
    if combined_ok or net_income_ok:
        score += 10
        feedback.append("Combined business income or net SE income found")
    elif se_marker:
        score += 5
        feedback.append("Self-employment marker found (T2125 used)")
    else:
        feedback.append("FAIL: Combined income/T2125 data not found")

    # --- Criterion 7: Business expense markers (vehicle CCA or expenses) (10 pts) ---
    vehicle_ok = result.get('contains_7679', False)
    cca_ok = result.get('contains_2697', False)
    if vehicle_ok and cca_ok:
        score += 10
        feedback.append("Vehicle expenses ($7,679) and CCA ($2,697) found")
    elif vehicle_ok or cca_ok:
        score += 5
        feedback.append("Partial business expense data found")
    else:
        feedback.append("FAIL: Vehicle/CCA business expenses not found")

    # --- Criterion 8: File size guard against stub (15 pts) ---
    # A properly completed SE return should be substantially larger than a simple T4 return
    file_size = result.get('file_size_bytes', 0)
    if file_size > 5000:
        score += 15
        feedback.append(f"File size adequate ({file_size} bytes)")
    elif file_size > 1000:
        score += 7
        feedback.append(f"File size marginal ({file_size} bytes)")
    else:
        feedback.append(f"FAIL: File too small ({file_size} bytes) — incomplete return")

    # --- Score cap gate: both income sources must be present to pass ---
    # This prevents wrong-target returns from passing on name alone
    if not (uber_ok and doordash_ok):
        score = min(score, 55)  # Cannot pass without both T4A amounts
        feedback.append("SCORE CAP: Both income sources required to pass")

    # 25 pts reserved for VLM evaluation
    return {
        "passed": score >= 60,
        "score": score,
        "feedback": " | ".join(feedback),
        "details": {"vlm_reserved": 25, "max_programmatic": 100},
        "subscores": {
            "file_saved": 15 if file_ok else 0,
            "timestamp": 10 if result.get('file_is_new') else 0,
            "name": 10 if name_ok else (5 if (result.get('contains_papadopoulos') or result.get('contains_dimitri')) else 0),
            "uber_income": 15 if uber_ok else 0,
            "doordash_income": 15 if doordash_ok else 0,
            "combined_income": 10 if (combined_ok or net_income_ok) else (5 if se_marker else 0),
            "business_expenses": 10 if (vehicle_ok and cca_ok) else (5 if (vehicle_ok or cca_ok) else 0),
            "file_size": 15 if file_size > 5000 else (7 if file_size > 1000 else 0),
            "vlm_evaluation": "pending"
        }
    }
