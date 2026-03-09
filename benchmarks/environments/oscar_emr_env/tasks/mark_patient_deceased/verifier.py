#!/usr/bin/env python3
"""
Verifier for mark_patient_deceased task.

Checks:
1. Patient status is 'DE' (Deceased).
2. Date of death matches the target date (Yesterday).
3. VLM verification of the workflow (optional but good for robustness).
"""

import json
import logging
import os
import tempfile
from datetime import datetime

# Import VLM helpers if available in the environment
try:
    from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot
except ImportError:
    # Fallback/mock for local testing
    def sample_trajectory_frames(traj, n=5): return []
    def get_final_screenshot(traj): return None

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_mark_patient_deceased(traj, env_info, task_info):
    """
    Verify Arthur Morgan was marked deceased with yesterday's date.
    """
    # 1. Setup & Data Retrieval
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System Error: copy_from_env not available"}

    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve task results: {str(e)}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    # 2. Extract Values
    final_status = result.get("final_status", "")
    final_date_of_death = result.get("final_date_of_death", "")
    target_date = result.get("target_date_of_death", "")
    
    # Handle potentially NULL or empty sql results
    if final_date_of_death in ["NULL", "None", None]:
        final_date_of_death = ""

    score = 0
    feedback = []

    # 3. Scoring Criteria

    # Criterion A: Status Update (40 points)
    # 'DE' is the standard code for Deceased in Oscar
    if final_status == 'DE':
        score += 40
        feedback.append("Success: Patient status updated to Deceased.")
    elif final_status == 'AC':
        feedback.append("Fail: Patient status is still Active.")
    else:
        # Partial credit for changing status to something else if applicable, but usually strict
        feedback.append(f"Fail: Patient status is '{final_status}' (expected 'DE').")

    # Criterion B: Date of Death Accuracy (60 points)
    # Full points for exact match
    if final_date_of_death and target_date and final_date_of_death == target_date:
        score += 60
        feedback.append(f"Success: Date of death correctly recorded as {target_date}.")
    elif final_date_of_death:
        # Check partial date match (e.g. if they entered today instead of yesterday)
        feedback.append(f"Fail: Date of death recorded as {final_date_of_death} (expected {target_date}).")
        # Anti-gaming: If they just put today's date (common mistake), give 10 pts for effort
        try:
            date_obj = datetime.strptime(final_date_of_death, "%Y-%m-%d")
            target_obj = datetime.strptime(target_date, "%Y-%m-%d")
            if abs((date_obj - target_obj).days) < 2:
                score += 10
                feedback.append("(Partial credit: Date is close)")
        except:
            pass
    else:
        feedback.append("Fail: No date of death recorded.")

    # 4. VLM Sanity Check (Tie-breaker/Penalty)
    # If DB says success but trajectory looks empty (anti-gaming via SQL injection),
    # we could penalize. For now, we trust the DB primarily but use VLM to verify UI interaction.
    frames = sample_trajectory_frames(traj, n=5)
    if not frames and score > 0:
        feedback.append("Warning: No visual evidence of UI interaction.")
        # In a strict environment, we might deduct points here.

    # 5. Final Verdict
    passed = (score >= 100)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }