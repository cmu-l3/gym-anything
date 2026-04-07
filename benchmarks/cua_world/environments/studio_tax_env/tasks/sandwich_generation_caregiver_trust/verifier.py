#!/usr/bin/env python3
"""
Verifier for sandwich_generation_caregiver_trust task.

David Alarie — Sandwich generation return.
T4 employment income ($62,000), T3 Trust Income ($12k CG, $4k div).
Prior year loss carry-forward ($5,000).
Spouse ($115k income), Childcare ($9,500), Dependant Parent ($18,400 income).
Dependant Medical Expenses ($6,800).

Scoring (100 pts total, pass threshold 60):
  Criterion 1: File saved correctly and > 500 bytes (15 pts)
  Criterion 2: Timestamp valid/modified during task (10 pts)
  Criterion 3: Taxpayer and Dependant names present (10 pts)
  Criterion 4: T4 employment income $62,000 present (10 pts)
  Criterion 5: T3 Trust allocations ($12,000 CG, $4,000 div) (15 pts)
  Criterion 6: Prior year Net Capital Loss applied $5,000 (10 pts)
  Criterion 7: Dependant Medical Expenses $6,800 (10 pts)
  Criterion 8: Childcare expenses $9,500 or max limit $8,000 (10 pts)
  Criterion 9: Spouse ($115k) and Parent ($18.4k) Net Incomes present (10 pts)

Score cap: T3 Trust Capital Gain ($12,000) or Employment Income ($62,000) must be 
present to pass. Missing both caps score at 50 to prevent blank-file gaming.
"""

import json
import os
import tempfile

def verify_sandwich_generation_caregiver_trust(traj, env_info, task_info):
    """Verify David Alarie's multi-generational return."""
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "No copy_from_env helper available."}

    # Retrieve the exported JSON result from the container
    try:
        with tempfile.NamedTemporaryFile(delete=False, suffix='.json') as f:
            temp_path = f.name
        
        copy_from_env("C:/Users/Docker/Desktop/sandwich_result.json", temp_path)
        
        with open(temp_path, 'r', encoding='utf-8-sig') as f:
            result = json.load(f)
            
        os.unlink(temp_path)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Could not read result JSON: {e}"}

    score = 0
    feedback = []

    # --- Criterion 1: File Saved (15 pts) ---
    file_ok = result.get('file_exists') and result.get('file_size_bytes', 0) > 500
    if file_ok:
        score += 15
        feedback.append("Return file 'david_alarie.24t' saved")
    else:
        feedback.append("FAIL: Return file not found or too small")

    # --- Criterion 2: Timestamp (10 pts) ---
    if result.get('file_is_new'):
        score += 10
        feedback.append("File timestamp valid")
    else:
        feedback.append("FAIL: File timestamp invalid (not created during session)")

    # --- Criterion 3: Family Names (10 pts) ---
    names = ['contains_alarie', 'contains_david', 'contains_sarah', 'contains_leo', 'contains_marie']
    found_names = [n for n in names if result.get(n)]
    if len(found_names) == 5:
        score += 10
        feedback.append("All family profiles (taxpayer, spouse, 2 dependants) found")
    elif len(found_names) >= 3:
        score += 5
        feedback.append("Most family profiles found")
    else:
        feedback.append("FAIL: Required family profile names missing")

    # --- Criterion 4: T4 Income (10 pts) ---
    if result.get('contains_62000'):
        score += 10
        feedback.append("T4 employment income $62,000 found")
    else:
        feedback.append("FAIL: T4 employment income missing")

    # --- Criterion 5: T3 Trust Allocations (15 pts) ---
    t3_cg = result.get('contains_12000')
    t3_div = result.get('contains_4000')
    if t3_cg and t3_div:
        score += 15
        feedback.append("T3 Trust allocations ($12,000 CG, $4,000 Div) found")
    elif t3_cg or t3_div:
        score += 7
        feedback.append("Partial T3 Trust allocations found")
    else:
        feedback.append("FAIL: T3 Trust allocations missing")

    # --- Criterion 6: Prior Year Loss Carry-Forward (10 pts) ---
    if result.get('contains_5000'):
        score += 10
        feedback.append("Prior year Net Capital Loss $5,000 applied")
    else:
        feedback.append("FAIL: Prior year Net Capital Loss missing")

    # --- Criterion 7: Dependant Medical (10 pts) ---
    if result.get('contains_6800'):
        score += 10
        feedback.append("Dependant medical expenses $6,800 found")
    else:
        feedback.append("FAIL: Dependant medical expenses missing")

    # --- Criterion 8: Childcare (10 pts) ---
    if result.get('contains_9500') or result.get('contains_8000'):
        score += 10
        feedback.append("Childcare expenses ($9,500 actual or $8,000 limit) found")
    else:
        feedback.append("FAIL: Childcare expenses missing")

    # --- Criterion 9: Dependant and Spouse Net Incomes (10 pts) ---
    inc_spouse = result.get('contains_115000')
    inc_parent = result.get('contains_18400')
    if inc_spouse and inc_parent:
        score += 10
        feedback.append("Spouse and dependant parent net incomes found")
    elif inc_spouse or inc_parent:
        score += 5
        feedback.append("Partial spouse/dependant parent income data found")
    else:
        feedback.append("FAIL: Spouse/parent income data missing")

    # --- Apply Anti-Gaming Score Cap ---
    # At minimum, some significant income (Employment or T3 Gains) must be entered to consider the file a real attempt
    if not result.get('contains_62000') and not result.get('contains_12000'):
        score = min(score, 50)
        feedback.append("SCORE CAPPED: Essential income markers missing. Prevents pass via blank/template file.")

    passed = score >= 60

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }