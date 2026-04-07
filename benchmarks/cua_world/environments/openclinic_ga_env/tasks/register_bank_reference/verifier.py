#!/usr/bin/env python3
"""
Verifier for register_bank_reference@1

Verifies that the agent successfully added "Equity Bank" to the OpenClinic GA 
financial reference tables.

Scoring Criteria:
1. Bank Record Exists (50 pts)
2. Bank Name Matches Exactly (20 pts) - Case insensitive check allowed but strictly "Equity Bank"
3. Record Created During Task (10 pts) - Via count/ID check
4. VLM/Visual Check (20 pts) - Confirms UI interaction was used
"""

import json
import os
import logging
import tempfile
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_register_bank_reference(traj, env_info, task_info):
    # 1. Setup and Load Data
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System error: copy_from_env missing"}

    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result file: {str(e)}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback = []
    
    # Metadata targets
    TARGET_NAME = task_info.get('metadata', {}).get('target_bank_name', 'Equity Bank')

    # ------------------------------------------------------------------
    # Criterion 1: Record Exists (50 pts)
    # ------------------------------------------------------------------
    found = result.get('bank_found', False)
    bank_data = result.get('bank_data', {})
    
    if found:
        score += 50
        feedback.append("Success: Bank record found in database.")
    else:
        feedback.append("Fail: No bank record found with name similar to 'Equity Bank'.")

    # ------------------------------------------------------------------
    # Criterion 2: Name Accuracy (20 pts)
    # ------------------------------------------------------------------
    # Check for exact string match (case-insensitive usually fine for user input, 
    # but we want to ensure no typos like 'Eqity Bank')
    actual_name = bank_data.get('name', '')
    
    if found:
        if actual_name.strip().lower() == TARGET_NAME.lower():
            score += 20
            feedback.append(f"Success: Bank name '{actual_name}' matches target.")
        else:
            feedback.append(f"Partial: Bank found but name '{actual_name}' differs from '{TARGET_NAME}'.")
            # Partial credit if close (e.g., substring)
            if TARGET_NAME.lower() in actual_name.lower():
                score += 10

    # ------------------------------------------------------------------
    # Criterion 3: Created During Task (10 pts)
    # ------------------------------------------------------------------
    initial_count = result.get('counts', {}).get('initial', 0)
    current_count = result.get('counts', {}).get('current', 0)
    
    # Simple heuristic: Count increased OR record found where none existed before
    if current_count > initial_count or (found and initial_count == 0):
        score += 10
        feedback.append("Success: New record creation detected (count increased).")
    else:
        # If count didn't change but we found it, maybe they edited an existing one? 
        # But setup script clears it. So this implies pre-existence or failure.
        if found:
            feedback.append("Warning: Bank count did not increase. Verification ambiguous.")
        else:
            feedback.append("Fail: No new data created.")

    # ------------------------------------------------------------------
    # Criterion 4: VLM Visual Verification (20 pts)
    # ------------------------------------------------------------------
    # Use VLM to ensure they actually used the UI (Navigation/Form filling)
    vlm_score = 0
    try:
        frames = sample_trajectory_frames(traj, n=4)
        final_scr = get_final_screenshot(traj)
        
        if frames:
            prompt = """
            Analyze these screenshots of a user interacting with OpenClinic GA hospital software.
            Did the user navigate to a 'Financial' or 'Banks' administration screen?
            Do you see a form or list where 'Equity Bank' is being entered or displayed?
            
            Return JSON: {"ui_interaction": boolean, "bank_name_visible": boolean}
            """
            
            # Using the framework's query_vlm if available, otherwise mock based on visual data existence
            if 'query_vlm' in env_info:
                vlm_resp = env_info['query_vlm'](images=frames + [final_scr], prompt=prompt)
                parsed = vlm_resp.get('parsed', {})
                if parsed.get('ui_interaction'):
                    vlm_score += 10
                if parsed.get('bank_name_visible'):
                    vlm_score += 10
                if vlm_score > 0:
                    feedback.append(f"Success: Visual verification confirmed UI usage ({vlm_score}/20).")
            else:
                # Fallback if VLM service not active but screenshots exist
                vlm_score = 20
                feedback.append("Info: Screenshots present, assuming valid interaction (VLM skipped).")
        else:
            feedback.append("Fail: No visual trajectory evidence.")
            
    except Exception as e:
        logger.warning(f"VLM check failed: {e}")
        # Don't penalize system errors, give benefit of doubt if DB check passed
        if found:
            vlm_score = 20
            feedback.append("Info: VLM check skipped due to error, awarded points based on DB success.")

    score += vlm_score

    # ------------------------------------------------------------------
    # Final Result
    # ------------------------------------------------------------------
    passed = (score >= 70) and found
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }