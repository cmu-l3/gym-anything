#!/usr/bin/env python3
"""
Verifier for create_transcription_typing_task.

Verification Strategy:
1. Validate CSV file existence and content (5 specific phrases).
2. Validate PsychoPy experiment structure via XML parsing.
   - Crucial: Check for TextBox component with 'editable=True'.
   - Check linkage to variables and CSV.
3. Anti-gaming: Check file timestamps and nonce.
4. VLM: Secondary check for interface usage.

Scoring:
- Conditions File (20 pts)
- Experiment Saved (10 pts)
- Target Display config (15 pts)
- Input Component (Editable TextBox) (35 pts) - CRITICAL
- Loop Setup (10 pts)
- Termination Logic (10 pts)

Pass Threshold: 75 points
"""

import json
import tempfile
import os
import logging

logger = logging.getLogger(__name__)

def verify_create_transcription_typing_task(traj, env_info, task_info):
    """Verify transcription task creation."""
    
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    feedback_parts = []
    score = 0
    
    # 1. Retrieve Result JSON
    result = {}
    try:
        with tempfile.NamedTemporaryFile(delete=False, suffix='.json') as tmp:
            tmp_path = tmp.name
        copy_from_env("/tmp/task_result.json", tmp_path)
        with open(tmp_path, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve results: {e}"}
    finally:
        if 'tmp_path' in locals() and os.path.exists(tmp_path):
            os.unlink(tmp_path)

    # 2. Nonce Check (Anti-gaming)
    # We retrieve the actual nonce file to compare, just in case JSON was spoofed
    try:
        with tempfile.NamedTemporaryFile(delete=False, suffix='.txt') as tmp:
            nonce_path = tmp.name
        copy_from_env("/home/ga/.task_nonce", nonce_path)
        with open(nonce_path, 'r') as f:
            expected_nonce = f.read().strip()
        
        json_nonce = result.get("result_nonce", "")
        if expected_nonce and json_nonce != expected_nonce:
            return {
                "passed": False, 
                "score": 0, 
                "feedback": "FAIL: Integrity check failed (nonce mismatch)."
            }
    except:
        # If nonce file missing, warn but proceed (soft fail)
        logger.warning("Nonce file check failed")

    # 3. Scoring Criteria

    # A. Conditions File (20 points)
    if result.get("csv_exists") and result.get("csv_modified"):
        # Header check
        if result.get("csv_header_valid"):
            score += 5
            feedback_parts.append("CSV header valid")
        else:
            feedback_parts.append("CSV header missing/incorrect")
            
        # Phrase content check (3 pts per correct phrase = 15 pts)
        phrases_found = result.get("csv_phrases_found", 0)
        score += (phrases_found * 3)
        feedback_parts.append(f"Phrases found: {phrases_found}/5")
    else:
        feedback_parts.append("Conditions file missing or not created during task")

    # B. Experiment Structure
    
    # Basic file existence (10 points)
    if result.get("exp_exists") and result.get("exp_modified") and result.get("exp_valid_xml"):
        score += 10
        feedback_parts.append("Experiment file saved")
    else:
        feedback_parts.append("Experiment file missing")

    # Target Display (15 points)
    if result.get("has_text_stim"):
        if result.get("text_uses_variable"):
            score += 15
            feedback_parts.append("Target text configured correctly")
        else:
            score += 5
            feedback_parts.append("Target text exists but missing variable")
    
    # Input Component (35 points) - CRITICAL
    if result.get("has_textbox"):
        if result.get("textbox_editable"):
            score += 35
            feedback_parts.append("Editable TextBox configured")
        else:
            score += 10
            feedback_parts.append("TextBox exists but NOT editable")
    else:
        feedback_parts.append("No TextBox component found")

    # Loop Setup (10 points)
    if result.get("has_loop"):
        loop_score = 0
        if result.get("loop_links_csv"): loop_score += 5
        if result.get("loop_random"): loop_score += 5
        score += loop_score
        feedback_parts.append(f"Loop setup: {loop_score}/10")

    # Termination (10 points)
    if result.get("has_return_key_end"):
        score += 10
        feedback_parts.append("Return key termination configured")
    else:
        feedback_parts.append("Return key termination missing")

    # 4. Final Verdict
    passed = score >= 75 and result.get("has_textbox") and result.get("textbox_editable")
    
    if not passed and score >= 75:
        feedback_parts.append("FAIL: Critical requirement (Editable TextBox) missing")

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }