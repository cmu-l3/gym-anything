#!/usr/bin/env python3
"""
Verifier for Chinook Accounts Receivable Workflow.

Verifies:
1. Schema modification (invoices table).
2. Logic for historical backfill (Paid vs Pending).
3. Logic for VIP exception (Customer 5).
4. Generation and correctness of Aging Report.
5. Evidence of DBeaver usage (Trajectory/VLM).
"""

import json
import os
import tempfile
from gym_anything.vlm import sample_trajectory_frames, query_vlm

def verify_chinook_ar_workflow(traj, env_info, task_info):
    # 1. Retrieve Result Data from Container
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result_data = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result data: {str(e)}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    # 2. Extract Data
    db_checks = result_data.get("db_checks", {})
    csv_exists = result_data.get("csv_exists", False)
    csv_fresh = result_data.get("csv_created_during_task", False)
    script_exists = result_data.get("script_exists", False)
    
    # 3. VLM Verification (Trajectory Analysis)
    # We want to confirm the user actually interacted with DBeaver SQL Editor or Table Editor
    frames = sample_trajectory_frames(traj, n=4)
    vlm_prompt = """
    Analyze these screenshots of a user working in DBeaver.
    Did the user:
    1. Have the 'invoices' table open or write SQL queries altering 'invoices'?
    2. Run SQL update/insert commands?
    
    Answer 'Yes' or 'No' and explain.
    """
    vlm_result = query_vlm(images=frames, prompt=vlm_prompt)
    vlm_passed = "yes" in str(vlm_result.get("response", "")).lower()

    # 4. Scoring Calculation
    score = 0
    feedback_lines = []

    # Criterion 1: Schema Modification (15 pts)
    if db_checks.get("schema_correct"):
        score += 15
        feedback_lines.append("✓ Schema modified correctly (PaymentStatus/Date columns added).")
    else:
        feedback_lines.append("✗ Schema modification failed or columns missing.")

    # Criterion 2: Backfill Logic - Pre-2013 (20 pts)
    if db_checks.get("rule_pre2013_correct"):
        score += 20
        feedback_lines.append("✓ Historical data (Pre-2013) correctly marked 'Paid'.")
    else:
        feedback_lines.append("✗ Historical data logic incorrect (Pre-2013).")

    # Criterion 3: Backfill Logic - Post-2013 (15 pts)
    if db_checks.get("rule_post2013_correct"):
        score += 15
        feedback_lines.append("✓ Recent data (Post-2013) correctly marked 'Pending'.")
    else:
        feedback_lines.append("✗ Recent data logic incorrect (Post-2013).")

    # Criterion 4: VIP Exception (20 pts)
    if db_checks.get("rule_vip_correct"):
        score += 20
        feedback_lines.append("✓ VIP Exception (Customer 5) correctly applied.")
    else:
        feedback_lines.append("✗ VIP Exception logic incorrect.")

    # Criterion 5: Report Creation (20 pts)
    if csv_exists and csv_fresh and db_checks.get("report_content_correct"):
        score += 20
        feedback_lines.append("✓ Aging report created with correct content.")
    elif csv_exists:
        score += 10
        feedback_lines.append("⚠ Aging report exists but content/headers validation failed.")
    else:
        feedback_lines.append("✗ Aging report not found.")

    # Criterion 6: SQL Script (10 pts)
    if script_exists:
        score += 10
        feedback_lines.append("✓ SQL setup script saved.")
    else:
        feedback_lines.append("✗ SQL script missing.")

    # Bonus/Penalty based on VLM
    if not vlm_passed and score > 0:
        feedback_lines.append("⚠ Note: Visual evidence of DBeaver usage was unclear.")

    passed = score >= 65

    return {
        "passed": passed,
        "score": score,
        "feedback": "\n".join(feedback_lines)
    }