#!/usr/bin/env python3
import json
import os
import base64
import csv
import io
import logging
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_record_portfolio_withdrawal(traj, env_info, task_info):
    """
    Verifies that a portfolio withdrawal was correctly recorded in JStock.
    """
    # 1. Setup and Load Data
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System error: copy_from_env not available"}

    metadata = task_info.get('metadata', {})
    expected_magnitude = metadata.get('expected_amount_magnitude', 2500.0)
    expected_date_part = metadata.get('expected_date_str', "Mar 10, 2024")
    
    # Load result from container
    import tempfile
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load task results: {str(e)}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback = []

    # 2. Verify File Modification (Anti-Gaming)
    if not result.get('target_file_exists'):
        return {"passed": False, "score": 0, "feedback": "Portfolio deposit file disappeared!"}

    if result.get('target_file_modified'):
        score += 10
        feedback.append("Portfolio file modified during task.")
    else:
        feedback.append("No changes detected in portfolio file.")
        # If file wasn't modified, they didn't save anything. Fail early.
        return {"passed": False, "score": 0, "feedback": "Task failed: No transaction saved (file not modified)."}

    # 3. Parse CSV Content
    content_b64 = result.get('target_file_content_b64', '')
    if not content_b64:
        return {"passed": False, "score": score, "feedback": "Portfolio file is empty."}

    try:
        csv_text = base64.b64decode(content_b64).decode('utf-8')
        f = io.StringIO(csv_text)
        reader = csv.reader(f)
        rows = list(reader)
    except Exception as e:
        return {"passed": False, "score": score, "feedback": f"Failed to parse portfolio CSV: {str(e)}"}

    # Check if we have data rows (Row 0 is header)
    if len(rows) < 2:
        return {"passed": False, "score": score, "feedback": "Portfolio file contains only header. No transaction recorded."}

    # Analyze the last row (assuming it's the one added)
    last_row = rows[-1]
    # Format: Date, Amount, Comment
    if len(last_row) < 3:
        return {"passed": False, "score": score, "feedback": "Transaction row format incorrect."}

    rec_date, rec_amount_str, rec_comment = last_row[0], last_row[1], last_row[2]

    # 4. Verify Transaction Logic (Withdrawal vs Deposit)
    try:
        rec_amount = float(rec_amount_str)
    except ValueError:
        return {"passed": False, "score": score, "feedback": f"Invalid amount format: {rec_amount_str}"}

    # CRITICAL CHECK: Sign of the amount
    # In JStock, withdrawals are negative numbers in the CSV
    if rec_amount < 0:
        score += 30
        feedback.append("Correctly recorded as a Withdrawal (negative value).")
        
        # Check magnitude
        if abs(abs(rec_amount) - expected_magnitude) < 0.01:
            score += 30
            feedback.append(f"Amount matches exactly (${expected_magnitude}).")
        else:
            feedback.append(f"Wrong amount: ${abs(rec_amount)} (Expected: ${expected_magnitude}).")
    else:
        # It's positive, meaning they recorded a Deposit
        feedback.append("ERROR: Transaction recorded as Deposit (positive) instead of Withdrawal (negative).")
        # No points for logic or amount if they got the sign wrong, as it's a fundamental accounting error.

    # 5. Verify Metadata (Date and Comment)
    if expected_date_part in rec_date:
        score += 15
        feedback.append(f"Date correct ({rec_date}).")
    else:
        feedback.append(f"Date incorrect: Found '{rec_date}', expected '{expected_date_part}'.")

    expected_keywords = metadata.get('expected_comment_keywords', [])
    if any(k.lower() in rec_comment.lower() for k in expected_keywords):
        score += 15
        feedback.append("Comment contains expected keywords.")
    else:
        feedback.append(f"Comment '{rec_comment}' missing keywords.")

    # 6. VLM Verification (Trajectory Analysis)
    # Even if file is correct, let's verify they actually used the UI
    try:
        frames = sample_trajectory_frames(traj, n=4)
        final = get_final_screenshot(traj)
        
        # We ask VLM if it sees the cash dialog
        vlm_score = 0
        prompt = "Look at these screenshots of JStock software. Did the user open a 'Cash Deposit' or 'Withdrawal' dialog box? Answer YES or NO."
        vlm_resp = query_vlm(frames, prompt).strip().lower()
        
        if "yes" in vlm_resp:
            vlm_score = 10
            feedback.append("VLM confirmed dialog usage.")
        
        # Add VLM points to total score, capping at 100
        score = min(100, score + vlm_score)
        
    except Exception as e:
        logger.warning(f"VLM verification failed: {e}")
        # Don't fail the task if VLM fails, just rely on file check

    passed = score >= 70
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }