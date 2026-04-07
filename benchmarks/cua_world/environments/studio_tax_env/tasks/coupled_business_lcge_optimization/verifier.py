#!/usr/bin/env python3
"""Verifier for coupled_business_lcge_optimization task.

Arjun & Meera Kapoor — Coupled spousal return with self-employment income,
QSBC Lifetime Capital Gains Exemption (T657), T2203 multi-province allocation,
dual T776 rental properties, DTC transfer, and family tax optimization.

This is a stub verifier. Full evaluation is performed externally via the
VLM checklist verifier (vlm_checklist_verifier.py). The programmatic checks
below provide basic validation of the output file.

Scoring (100 pts total, pass threshold 60):
  Criterion 1: File saved correctly (10 pts)
  Criterion 2: Timestamp valid (5 pts)
  Criterion 3: Both spouse names present — coupled return (10 pts)
  Criterion 4: Arjun's T2125 business income (10 pts)
  Criterion 5: QSBC capital gain $328,000 (10 pts)
  Criterion 6: T2203 BC/AB allocation (8 pts)
  Criterion 7: Meera's T4 employment income (8 pts)
  Criterion 8: T776 rental income — at least one property (7 pts)
  Criterion 9: Medical expenses (5 pts)
  Criterion 10: Childcare (5 pts)
  Criterion 11: DTC / Rohan present — $15,630 (5 pts)
  Criterion 12: Donations present (5 pts)
  Criterion 13: RRSP present (5 pts)
  Criterion 14: VLM reserved (7 pts)

Score caps:
  - If both T2125 and T4 income missing: max 25
  - If QSBC gain missing: max 55
  - If neither spouse name found: max 15
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_coupled_business_lcge_optimization(traj, env_info, task_info):
    """Verify Kapoor family coupled return with LCGE and optimization."""
    score = 0
    feedback = []

    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "No copy_from_env helper"}

    # Retrieve programmatic results from Windows environment
    try:
        with tempfile.NamedTemporaryFile(delete=False, suffix='.json') as f:
            temp_path = f.name
        copy_from_env("C:/Users/Docker/Desktop/kapoor_result.json", temp_path)
        with open(temp_path, 'r', encoding='utf-8-sig') as f:
            result = json.load(f)
        os.unlink(temp_path)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Could not read result: {e}"}

    # --- Criterion 1: File saved correctly (10 pts) ---
    file_ok = result.get('file_exists') and result.get('file_size_bytes', 0) > 1000
    if file_ok:
        score += 10
        feedback.append("Return file 'kapoor_family.24t' saved with valid size")
    else:
        feedback.append("FAIL: Return file not found or too small")

    # --- Criterion 2: Timestamp valid (5 pts) ---
    if result.get('file_is_new'):
        score += 5
        feedback.append("File timestamp valid")
    else:
        feedback.append("FAIL: File timestamp predates task start")

    # --- Criterion 3: Both spouse names — coupled return (10 pts) ---
    has_arjun = result.get('contains_arjun', False)
    has_meera = result.get('contains_meera', False)
    has_kapoor = result.get('contains_kapoor', False)
    if has_arjun and has_meera and has_kapoor:
        score += 10
        feedback.append("Both Arjun and Meera Kapoor found (coupled return)")
    elif (has_arjun or has_meera) and has_kapoor:
        score += 5
        feedback.append("Only one spouse name found")
    elif has_kapoor:
        score += 3
        feedback.append("Kapoor surname found but first names missing")
    else:
        feedback.append("FAIL: Spouse names not found")

    # --- Criterion 4: Arjun's T2125 business income (10 pts) ---
    has_net_business = result.get('contains_155400', False)
    has_gross_business = result.get('contains_195000', False)
    if has_net_business and has_gross_business:
        score += 10
        feedback.append("T2125 net ($155,400) and gross ($195,000) business income found")
    elif has_net_business or has_gross_business:
        score += 7
        feedback.append("Partial T2125 business income found")
    else:
        feedback.append("FAIL: T2125 business income not found")

    has_business = has_net_business or has_gross_business

    # --- Criterion 5: QSBC capital gain $328,000 (10 pts) ---
    has_qsbc_gain = result.get('contains_328000', False)
    has_qsbc_proceeds = result.get('contains_390000', False)
    qsbc_ok = has_qsbc_gain or has_qsbc_proceeds
    if has_qsbc_gain:
        score += 10
        feedback.append("QSBC capital gain $328,000 found")
    elif has_qsbc_proceeds:
        score += 7
        feedback.append("QSBC proceeds $390,000 found but gain not confirmed")
    else:
        feedback.append("FAIL: QSBC capital gain data not found")

    # --- Criterion 6: T2203 BC/AB allocation (8 pts) ---
    has_bc_alloc = result.get('contains_126750', False)
    has_ab_alloc = result.get('contains_68250', False)
    if has_bc_alloc and has_ab_alloc:
        score += 8
        feedback.append("T2203 BC ($126,750) and AB ($68,250) allocation found")
    elif has_bc_alloc or has_ab_alloc:
        score += 4
        feedback.append("Partial T2203 allocation found")
    else:
        feedback.append("FAIL: T2203 multi-province allocation not found")

    # --- Criterion 7: Meera's T4 employment income (8 pts) ---
    has_t4 = result.get('contains_48600', False)
    if has_t4:
        score += 8
        feedback.append("Meera's T4 employment income $48,600 found")
    else:
        feedback.append("FAIL: T4 employment income $48,600 not found")

    # --- Criterion 8: T776 rental income (7 pts) ---
    has_rental1 = result.get('contains_26400', False)
    has_rental2 = result.get('contains_8400', False)
    if has_rental1 and has_rental2:
        score += 7
        feedback.append("Both rental properties ($26,400 and $8,400) found")
    elif has_rental1 or has_rental2:
        score += 4
        feedback.append("One rental property found")
    else:
        feedback.append("FAIL: Rental income data not found")

    # --- Criterion 9: Medical expenses (5 pts) ---
    if result.get('contains_6830', False):
        score += 5
        feedback.append("Medical expenses $6,830 found")
    else:
        feedback.append("FAIL: Medical expenses not found")

    # --- Criterion 10: Childcare (5 pts) ---
    if result.get('contains_8000', False):
        score += 5
        feedback.append("Childcare $8,000 found")
    else:
        feedback.append("FAIL: Childcare not found")

    # --- Criterion 11: DTC / Rohan (5 pts) ---
    has_rohan = result.get('contains_rohan', False)
    has_dtc = result.get('contains_15630', False)
    if has_rohan or has_dtc:
        score += 5
        feedback.append("DTC data (Rohan / $15,630) found")
    else:
        feedback.append("FAIL: DTC data not found")

    # --- Criterion 12: Donations (5 pts) ---
    has_donations = (result.get('contains_8200', False) or
                     result.get('contains_5400', False) or
                     result.get('contains_2800', False))
    if has_donations:
        score += 5
        feedback.append("Charitable donation data found")
    else:
        feedback.append("FAIL: Donation data not found")

    # --- Criterion 13: RRSP (5 pts) ---
    if result.get('contains_22000', False):
        score += 5
        feedback.append("RRSP $22,000 found")
    else:
        feedback.append("FAIL: RRSP not found")

    # --- Criterion 14: VLM reserved (7 pts) ---
    # Stub — full VLM evaluation is handled externally by vlm_checklist_verifier
    feedback.append("VLM evaluation reserved (7 pts) — handled by external verifier")

    # --- Score Caps ---
    if not (has_business or has_t4):
        score = min(score, 25)
        feedback.append("SCORE CAP 25: Both T2125 and T4 income missing")
    if not qsbc_ok:
        score = min(score, 55)
        feedback.append("SCORE CAP 55: QSBC capital gain data missing")
    if not (has_arjun or has_meera):
        score = min(score, 15)
        feedback.append("SCORE CAP 15: No spouse names found")

    passed = score >= 60

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback),
        "details": {"vlm_reserved": 7, "max_programmatic": 93},
    }
