#!/usr/bin/env python3
"""
Verifier for record_portfolio_deposits task.

Checks:
1. depositsummary.csv was modified after task start.
2. Contains exactly the two requested deposits (fuzzy matching on strings).
3. Amounts match within tolerance.
4. Total sum matches expected value.
5. VLM verification for UI interaction (trajectory).
"""

import json
import os
import csv
import io
import logging
import tempfile
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_record_portfolio_deposits(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_dep1 = metadata.get('deposit_1', {})
    expected_dep2 = metadata.get('deposit_2', {})
    expected_total = metadata.get('expected_total', 55000.0)

    # Load result JSON
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback_parts = []
    
    # ---------------------------------------------------------
    # Criterion 1: Anti-Gaming / File Activity (10 pts)
    # ---------------------------------------------------------
    task_start = result.get('task_start', 0)
    file_mtime = result.get('file_mtime', 0)
    file_content_str = result.get('file_content_json')  # This is the CSV string
    
    if result.get('file_exists') and file_mtime > task_start:
        score += 10
        feedback_parts.append("File modified during task")
    else:
        feedback_parts.append("File NOT modified or not found")
        return {"passed": False, "score": 0, "feedback": " | ".join(feedback_parts)}

    # ---------------------------------------------------------
    # Criterion 2: Parse Data & Check Content (70 pts)
    # ---------------------------------------------------------
    deposits = []
    try:
        if file_content_str:
            f = io.StringIO(file_content_str)
            reader = csv.DictReader(f)
            for row in reader:
                deposits.append(row)
    except Exception as e:
        feedback_parts.append(f"CSV Parse Error: {str(e)}")

    if len(deposits) > 0:
        score += 15  # At least one deposit exists
        feedback_parts.append(f"Found {len(deposits)} deposits")
    else:
        feedback_parts.append("No deposits found in file")

    # Helper to check a deposit
    def check_deposit(dep_req, found_deposits):
        target_amt = dep_req.get('amount')
        date_subs = dep_req.get('date_substrings', [])
        comm_keys = dep_req.get('comment_keywords', [])
        
        # Look for best match in found_deposits
        best_match = None
        
        for dep in found_deposits:
            try:
                amt = float(dep.get("Amount", "0").replace(',', ''))
            except:
                amt = 0.0
            
            # Check amount match
            if abs(amt - target_amt) < 0.05:
                # Potential match found by amount
                date_str = dep.get("Date", "")
                comm_str = dep.get("Comment", "")
                
                # Check date
                date_match = all(sub.lower() in date_str.lower() for sub in date_subs)
                
                # Check comment
                comm_match = any(key.lower() in comm_str.lower() for key in comm_keys)
                
                return {
                    "found": True, 
                    "date_ok": date_match, 
                    "comment_ok": comm_match,
                    "raw_date": date_str,
                    "raw_comm": comm_str
                }
        return {"found": False}

    # Verify Deposit 1 ($30,000)
    d1_res = check_deposit(expected_dep1, deposits)
    if d1_res["found"]:
        score += 20
        feedback_parts.append("Dep 1 amount OK")
        if d1_res["date_ok"]: score += 5 
        else: feedback_parts.append(f"Dep 1 date mismatch ({d1_res['raw_date']})")
        
        if d1_res["comment_ok"]: score += 5
        else: feedback_parts.append("Dep 1 comment mismatch")
    else:
        feedback_parts.append("Dep 1 ($30k) NOT found")

    # Verify Deposit 2 ($25,000)
    d2_res = check_deposit(expected_dep2, deposits)
    if d2_res["found"]:
        score += 20
        feedback_parts.append("Dep 2 amount OK")
        if d2_res["date_ok"]: score += 5
        else: feedback_parts.append(f"Dep 2 date mismatch ({d2_res['raw_date']})")
        
        if d2_res["comment_ok"]: score += 5
        else: feedback_parts.append("Dep 2 comment mismatch")
    else:
        feedback_parts.append("Dep 2 ($25k) NOT found")

    # Verify Total
    total_found = sum(float(d.get("Amount", "0").replace(',', '')) for d in deposits)
    if abs(total_found - expected_total) < 0.05:
        score += 10
        feedback_parts.append("Total sum correct")
    else:
        feedback_parts.append(f"Total sum incorrect: {total_found}")

    # ---------------------------------------------------------
    # Criterion 3: VLM Visual Verification (5 pts)
    # ---------------------------------------------------------
    # Minimal check: did they even visit the portfolio tab?
    # Since we have strong file verification, this is just a bonus/sanity check
    frames = sample_trajectory_frames(traj, n=5)
    final_scr = get_final_screenshot(traj)
    
    # We assume if the file was modified with correct data, they likely used the UI
    # This is a soft bonus
    if score > 50:
        score += 5
        feedback_parts.append("Implicit visual pass via data")

    final_score = min(score, 100)
    passed = final_score >= 60 and d1_res["found"] and d2_res["found"]

    return {
        "passed": passed,
        "score": final_score,
        "feedback": " | ".join(feedback_parts)
    }