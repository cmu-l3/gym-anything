#!/usr/bin/env python3
"""Verifier for ecommerce_cogs_interprovincial_tax task.

Chloe Tremblay — E-commerce sole proprietor with out-of-province employment.
Tests T2125 Cost of Goods Sold (COGS) tracking, inter-provincial tax flags, 
business-use-of-home expenses, and medical expense entry.

Scoring (100 pts total, pass threshold 60):
  Criterion 1: File saved correctly and valid size (10 pts)
  Criterion 2: Taxpayer Name and Province (NB) (10 pts)
  Criterion 3: T4 Box 14 and Box 22 entry (10 pts)
  Criterion 4: Inter-provincial ON flag present (15 pts)
  Criterion 5: T2125 Gross Sales present (10 pts)
  Criterion 6: T2125 COGS structure complete (20 pts)
  Criterion 7: T2125 General expenses present (10 pts)
  Criterion 8: Business-use-of-home present (10 pts)
  Criterion 9: Medical expenses present (5 pts)

Score cap: At least one COGS entry MUST be present. If absent, score is capped at 55.
"""

import json
import os
import tempfile

def verify_ecommerce_cogs_interprovincial_tax(traj, env_info, task_info):
    """Verify Chloe Tremblay e-commerce return."""
    score = 0
    feedback = []

    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "No copy_from_env helper"}

    # Use copy_from_env to securely fetch the resulting verification data
    temp_path = tempfile.mktemp(suffix='.json')
    try:
        copy_from_env("C:/Users/Docker/Desktop/ecommerce_result.json", temp_path)
        with open(temp_path, 'r', encoding='utf-8') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Could not read result: {e}"}
    finally:
        if os.path.exists(temp_path):
            os.unlink(temp_path)

    # --- Criterion 1: File saved with correct name (10 pts) ---
    file_ok = result.get('file_exists', False) and result.get('file_size_bytes', 0) > 500
    if file_ok:
        score += 10
        feedback.append("Return file 'chloe_tremblay.24t' saved (> 500 bytes)")
    else:
        feedback.append("FAIL: Return file not found or too small")

    # Anti-gaming timestamp check
    if not result.get('file_is_new', False):
        feedback.append("WARNING: File timestamp check failed (Pre-existing file?)")

    # --- Criterion 2: Taxpayer name and Province (10 pts) ---
    name_prov_ok = result.get('contains_chloe', False) and result.get('contains_nb', False)
    if name_prov_ok:
        score += 10
        feedback.append("Taxpayer Name (Chloe) and Province (NB) found")
    else:
        feedback.append("FAIL: Name or Province missing")

    # --- Criterion 3: T4 Income & Withheld Tax (10 pts) ---
    t4_ok = result.get('contains_68450', False) and result.get('contains_10250', False)
    if t4_ok:
        score += 10
        feedback.append("T4 Box 14 ($68,450) and Box 22 ($10,250) found")
    elif result.get('contains_68450', False):
        score += 5
        feedback.append("T4 Box 14 ($68,450) found, but Box 22 missing")
    else:
        feedback.append("FAIL: T4 Income $68,450 not found")

    # --- Criterion 4: Inter-provincial flag ON (15 pts) ---
    on_flag = result.get('contains_on', False)
    if on_flag:
        score += 15
        feedback.append("Inter-provincial employment flag (ON) found")
    else:
        feedback.append("FAIL: Inter-provincial flag 'ON' not found")

    # --- Criterion 5: T2125 Gross Sales (10 pts) ---
    gross_ok = result.get('contains_45750', False)
    if gross_ok:
        score += 10
        feedback.append("T2125 Gross Sales ($45,750) found")
    else:
        feedback.append("FAIL: T2125 Gross Sales not found")

    # --- Criterion 6: T2125 COGS Structure (20 pts) ---
    # Need to distinguish COGS properly. If all 3 are present, it's fully structured.
    cogs_items = sum([
        result.get('contains_5240', False),
        result.get('contains_12860', False),
        result.get('contains_4110', False)
    ])
    if cogs_items == 3:
        score += 20
        feedback.append("T2125 COGS correctly structured (Opening, Purchases, Closing)")
    elif cogs_items >= 1:
        score += 10
        feedback.append(f"Partial T2125 COGS structure ({cogs_items}/3 items found)")
    else:
        feedback.append("FAIL: T2125 COGS structure entirely missing")

    # --- Criterion 7: T2125 General Expenses (10 pts) ---
    exp_items = sum([
        result.get('contains_4820', False),
        result.get('contains_2150', False),
        result.get('contains_3550', False)
    ])
    if exp_items == 3:
        score += 10
        feedback.append("T2125 General Expenses found")
    elif exp_items >= 1:
        score += 5
        feedback.append(f"Partial T2125 General Expenses ({exp_items}/3 items found)")
    else:
        feedback.append("FAIL: T2125 General Expenses missing")

    # --- Criterion 8: Business-Use-of-Home (10 pts) ---
    home_items = sum([
        result.get('contains_18000', False),
        result.get('contains_1200', False)
    ])
    if home_items == 2:
        score += 10
        feedback.append("Business-Use-of-Home expenses found")
    elif home_items == 1:
        score += 5
        feedback.append("Partial Business-Use-of-Home expenses found")

    # --- Criterion 9: Medical Expenses (5 pts) ---
    medical = result.get('contains_4600', False)
    if medical:
        score += 5
        feedback.append("Medical expenses ($4,600) found")

    # Evaluate pass condition & apply structural score caps
    passed = score >= 60 and cogs_items >= 1
    
    # Cap score below pass threshold if the core task objective (COGS) is ignored
    if not passed and score >= 60:
        feedback.append("FAIL: Score cap applied - At least one COGS entry is required to pass")
        score = 55

    return {"passed": passed, "score": score, "feedback": " | ".join(feedback)}