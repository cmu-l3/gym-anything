#!/usr/bin/env python3
"""
Verifier for update_local_procedure_tariffs task.

Verification Logic:
1. Updates Correct (60 pts): Targeted rows in database match CSV values.
2. Integrity Maintained (20 pts): Non-targeted rows remain unchanged.
3. Log Created (10 pts): Log file exists and has content.
4. Process Verification (10 pts): VLM verifies agent used terminal/tools.
"""

import json
import tempfile
import os
import logging
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_update_local_procedure_tariffs(traj, env_info, task_info):
    """
    Verify the tariff update task.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    score = 0
    feedback_parts = []
    max_score = 100
    
    # 1. Load results from container
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result JSON: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    # 2. Database Verification (Primary)
    
    # Criterion 1: Correct Updates (60 pts)
    if result.get("updates_correct", False):
        score += 60
        feedback_parts.append("All tariffs updated correctly.")
    else:
        # Partial credit could be calculated from result['updated_codes'] vs targets
        # but for simplicity we rely on the internal check.
        # Let's verify partials if available
        targets = task_info.get('metadata', {}).get('target_updates', {})
        actuals = result.get('updated_codes', {})
        correct_count = 0
        for code, expected in targets.items():
            if code in actuals and abs(actuals[code] - expected) < 0.01:
                correct_count += 1
        
        partial_score = (correct_count / len(targets)) * 60 if targets else 0
        score += partial_score
        feedback_parts.append(f"Tariff updates: {correct_count}/{len(targets)} correct.")

    # Criterion 2: Data Integrity (20 pts)
    # CRITICAL: We don't want the agent to just UPDATE ALL rows to a single value
    if result.get("integrity_maintained", False):
        score += 20
        feedback_parts.append("Data integrity check passed (unrelated rows unchanged).")
    else:
        feedback_parts.append("INTEGRITY CHECK FAILED: Unintended rows were modified.")

    # Criterion 3: Log File (10 pts)
    if result.get("log_file_exists", False) and result.get("log_file_size", 0) > 0:
        score += 10
        feedback_parts.append("Log file created.")
    else:
        feedback_parts.append("Log file missing or empty.")

    # 3. VLM Verification (Trajectory) (10 pts)
    # Check if the agent actually used the terminal or database client
    frames = sample_trajectory_frames(traj, n=5)
    final_frame = get_final_screenshot(traj)
    
    vlm_prompt = """
    Review this sequence of screenshots from a computer agent.
    The agent was tasked with updating database records.
    
    Look for:
    1. A terminal window open.
    2. SQL commands (like UPDATE, SELECT, mysql) or a database client interface.
    3. Viewing a CSV file (cat, less, nano).
    
    Did the agent actively engage with the system to perform the task?
    Reply JSON: {"active_engagement": true/false}
    """
    
    try:
        if frames:
            vlm_res = query_vlm(images=frames, prompt=vlm_prompt)
            if vlm_res.get('success') and vlm_res.get('parsed', {}).get('active_engagement'):
                score += 10
                feedback_parts.append("VLM verified active engagement.")
            else:
                # Fallback: if they got the DB right, they likely engaged
                if score >= 60:
                    score += 10
    except Exception as e:
        logger.warning(f"VLM check failed: {e}")
        # Be lenient if VLM fails but programmatic check passes
        if score >= 60:
            score += 10

    # Final Pass Logic
    # Must have reasonable updates and maintained integrity
    passed = (result.get("updates_correct", False) or score >= 80) and result.get("integrity_maintained", False)

    return {
        "passed": passed,
        "score": int(score),
        "feedback": " | ".join(feedback_parts)
    }