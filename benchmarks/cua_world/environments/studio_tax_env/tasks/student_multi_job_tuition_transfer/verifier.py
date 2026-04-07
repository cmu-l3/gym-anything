#!/usr/bin/env python3
"""Verifier for student_multi_job_tuition_transfer task.

Jasmine Chen — full-time university student.
Three T4s (two AB, one BC), fully exempt scholarship, T2202 tuition transferred to parent.
Crucially checks that moving expenses were NOT claimed since scholarship is exempt.

Scoring (100 pts total, pass threshold 60):
  Criterion 1: File saved correctly (15 pts)
  Criterion 2: Timestamp valid (10 pts)
  Criterion 3: Taxpayer name present (10 pts)
  Criterion 4: T4 incomes present (3x10 = 30 pts)
  Criterion 5: Scholarship $15,000 present (10 pts)
  Criterion 6: Tuition $8,740 present (10 pts)
  Criterion 7: Student loan interest $680 present (5 pts)
  Criterion 8: Tuition transfer to parent Wei present (10 pts)
  Penalty: Moving expenses $2,513 entered (-10 pts)

Score cap: At least two out of three T4 employment incomes must be present to pass.
"""

import json
import os
import tempfile


def verify_student_multi_job_tuition_transfer(traj, env_info, task_info):
    """Verify Jasmine Chen student multi-job return."""
    score = 0
    feedback = []

    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "No copy_from_env helper"}

    try:
        with tempfile.NamedTemporaryFile(delete=False, suffix='.json') as f:
            temp_path = f.name
        copy_from_env("C:/Users/Docker/Desktop/student_result.json", temp_path)
        with open(temp_path, 'r', encoding='utf-8-sig') as f:
            result = json.load(f)
        os.unlink(temp_path)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Could not read result: {e}"}

    # --- Criterion 1: File saved with correct name (15 pts) ---
    file_ok = result.get('file_exists') and result.get('file_size_bytes', 0) > 500
    if file_ok:
        score += 15
        feedback.append("Return file 'jasmine_chen.24t' saved")
    else:
        feedback.append("FAIL: Return file not found or too small")

    # --- Criterion 2: Timestamp valid (10 pts) ---
    if result.get('file_is_new'):
        score += 10
        feedback.append("File timestamp valid")
    else:
        feedback.append("FAIL: File timestamp invalid")

    # --- Criterion 3: Taxpayer name (10 pts) ---
    name_ok = result.get('contains_chen') and result.get('contains_jasmine')
    if name_ok:
        score += 10
        feedback.append("Taxpayer name (Jasmine Chen) found")
    else:
        feedback.append("FAIL: Taxpayer name not found")

    # --- Criterion 4: T4 employment incomes (3x10 = 30 pts) ---
    t4_count = sum([
        result.get('contains_8240', False),
        result.get('contains_6180', False),
        result.get('contains_4960', False)
    ])
    if t4_count == 3:
        score += 30
        feedback.append("All three T4 employment incomes found")
    elif t4_count > 0:
        score += t4_count * 10
        feedback.append(f"Partial T4 employment incomes found ({t4_count}/3)")
    else:
        feedback.append("FAIL: No T4 employment incomes found")

    # --- Criterion 5: Scholarship T4A $15,000 (10 pts) ---
    if result.get('contains_15000', False):
        score += 10
        feedback.append("Scholarship $15,000 found")
    else:
        feedback.append("FAIL: Scholarship $15,000 not found")

    # --- Criterion 6: Tuition T2202 $8,740 (10 pts) ---
    if result.get('contains_8740', False):
        score += 10
        feedback.append("Tuition $8,740 found")
    else:
        feedback.append("FAIL: Tuition $8,740 not found")

    # --- Criterion 7: Student loan interest $680 (5 pts) ---
    if result.get('contains_680', False):
        score += 5
        feedback.append("Student loan interest $680 found")
    else:
        feedback.append("FAIL: Student loan interest $680 not found")

    # --- Criterion 8: Tuition transfer to parent Wei (10 pts) ---
    transfer_ok = result.get('contains_wei', False) or result.get('contains_5000', False)
    if transfer_ok:
        score += 10
        feedback.append("Tuition transfer to parent found")
    else:
        feedback.append("FAIL: Tuition transfer to parent not found")

    # --- PENALTY: Moving expenses trap ---
    # Moving expenses cannot be deducted against employment income, only against scholarship income.
    # Because the scholarship is fully exempt, moving expenses are not deductible in 2024.
    if result.get('contains_2513', False):
        score -= 10
        feedback.append("PENALTY (-10): Moving expenses ($2,513) incorrectly claimed. They cannot be deducted against a fully exempt scholarship.")
    else:
        feedback.append("Moving expenses correctly omitted (or carried forward at $0).")

    # Pass logic: Must reach threshold and have entered at least 2 out of the 3 T4 jobs.
    passed = score >= 60 and t4_count >= 2
    
    if t4_count < 2:
        feedback.append("Score capped: Must have at least two T4 incomes to pass.")
        score = min(score, 50)
        passed = False

    return {
        "passed": passed,
        "score": max(0, score),
        "feedback": " | ".join(feedback)
    }