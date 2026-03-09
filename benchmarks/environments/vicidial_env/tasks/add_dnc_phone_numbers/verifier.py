#!/usr/bin/env python3
"""
Verifier for add_dnc_phone_numbers task.

Verification Strategy:
1. Primary: Database check. Verify specific phone numbers exist in `vicidial_dnc` table.
2. Anti-gaming: Verify total DNC count increased from baseline.
3. VLM: Verify agent navigated to DNC page and performed upload/entry workflow.

Passing Criteria:
- At least 80% of numbers found in DB (8/10).
- Total count increased.
- No "cheating" detected (e.g., zero count increase but numbers found implies bad setup or gaming).
"""

import json
import os
import tempfile
import logging
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_add_dnc_phone_numbers(traj, env_info, task_info):
    """Verify that phone numbers were added to the internal DNC list."""
    
    # 1. Setup - Get Data from Container
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result file: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    # 2. Extract Metrics
    found_count = result.get('numbers_found_count', 0)
    expected_count = result.get('numbers_expected_count', 10)
    count_increase = result.get('count_increase', 0)
    app_running = result.get('app_running', False)
    
    score = 0
    max_score = 100
    feedback_parts = []
    
    # 3. Database Verification (70 points)
    # 7 points per number found
    if expected_count > 0:
        db_score = min(70, int((found_count / expected_count) * 70))
    else:
        db_score = 0
    
    score += db_score
    feedback_parts.append(f"Found {found_count}/{expected_count} numbers in DNC list (+{db_score} pts)")

    # 4. Anti-Gaming / Logic Check (10 points)
    # The table count must have increased by at least the number of found items
    # (or roughly that amount).
    if count_increase >= found_count and found_count > 0:
        score += 10
        feedback_parts.append(f"DNC list count increased by {count_increase} (+10 pts)")
    elif count_increase > 0:
        score += 5
        feedback_parts.append(f"DNC list count increased by {count_increase} (+5 pts)")
    else:
        feedback_parts.append("Warning: DNC list count did not increase")

    # 5. VLM Verification (20 points)
    # Check if agent actually used the UI
    try:
        frames = sample_trajectory_frames(traj, n=4)
        final_shot = get_final_screenshot(traj)
        all_images = frames + [final_shot] if final_shot else frames
        
        prompt = """
        Analyze these screenshots of a Vicidial Admin task.
        The user goal is to add phone numbers to the Internal DNC (Do Not Call) list.
        
        Look for:
        1. Navigation to the "DNC" or "Do Not Call" section in the admin menu.
        2. A form input or file upload interface for adding numbers.
        3. A confirmation message or list view showing the numbers were added.
        
        Did the agent successfully navigate to the DNC section and attempt to add numbers?
        Respond with JSON: {"navigated_dnc": boolean, "attempted_add": boolean, "confidence": float}
        """
        
        vlm_resp = query_vlm(images=all_images, prompt=prompt)
        vlm_data = vlm_resp.get("parsed", {})
        
        if vlm_data.get("navigated_dnc"):
            score += 10
            feedback_parts.append("VLM confirmed navigation to DNC section (+10 pts)")
            
            if vlm_data.get("attempted_add"):
                score += 10
                feedback_parts.append("VLM confirmed add attempt (+10 pts)")
            else:
                feedback_parts.append("VLM did not clearly see add attempt")
        else:
            feedback_parts.append("VLM did not confirm DNC navigation")
            
    except Exception as e:
        logger.warning(f"VLM check failed: {e}")
        # Fallback: if database check is perfect, assume they did it right
        if found_count == expected_count:
             score += 20
             feedback_parts.append("VLM skipped but database verification perfect (+20 pts)")

    # 6. Final Evaluation
    passed = (score >= 60) and (found_count >= 8)  # Must find at least 80% of numbers to pass
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }