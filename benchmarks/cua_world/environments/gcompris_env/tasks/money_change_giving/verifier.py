#!/usr/bin/env python3
"""
Verifier for GCompris Money Change Giving task.

VERIFICATION STRATEGY:
1. File Evidence (40 points):
   - Check if agent created the two required screenshots.
   - Verify timestamps (anti-gaming).
   
2. VLM Trajectory Verification (60 points):
   - Activity ID: Did agent find "Give Change" (subtraction) vs "Pay" (counting)?
   - Logic: Did agent calculate Paid - Price?
   - Progression: Evidence of multiple rounds/success feedback.
"""

import json
import os
import tempfile
import logging
from typing import Dict, Any

# Gym-Anything VLM helpers
try:
    from gym_anything.vlm import sample_trajectory_frames, query_vlm
except ImportError:
    # Fallback for local testing
    def sample_trajectory_frames(traj, n=5): return []
    def query_vlm(prompt, images): return {"success": False, "error": "VLM unavailable"}

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

VLM_PROMPT = """
You are verifying an agent training on the "Give Change" activity in GCompris.
In this activity, the screen shows an item Price and an amount Paid. The user must return the difference (Paid - Price).
This is DIFFERENT from the "Pay" activity where the user just counts money to match a price.

Analyze the sequence of screenshots and the final provided screenshots.

Check for these specific criteria:
1. **Correct Activity**: Does the interface show BOTH "Price" and "Paid" (or "To pay" and "Paid") values? Or text like "Give back..."? (If it only shows one price to match, it's the WRONG activity).
2. **Subtraction Logic**: Does the agent select coins that represent the difference? (e.g. Price $14, Paid $20 -> Agent drags $5 and $1).
3. **Progression**: Do you see multiple different transaction amounts or the Tux mascot appearing to indicate success/next level?
4. **Completion**: Did the agent complete approximately 5 rounds?

Respond in JSON format:
{
    "correct_activity_give_change": true/false,
    "wrong_activity_simple_pay": true/false,
    "progression_observed": true/false,
    "rounds_completed_estimate": "number or range",
    "confidence": "high/medium/low",
    "feedback": "explanation of what was observed"
}
"""

def verify_money_change_giving(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # 1. Load File Evidence
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            file_result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result JSON: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback_parts = []

    # 2. Score File Evidence (40 pts)
    ui_ss = file_result.get('ui_screenshot', {})
    comp_ss = file_result.get('completion_screenshot', {})

    if ui_ss.get('exists') and ui_ss.get('created_during_task'):
        score += 20
        feedback_parts.append("UI screenshot created.")
    
    if comp_ss.get('exists') and comp_ss.get('created_during_task'):
        score += 20
        feedback_parts.append("Completion screenshot created.")
    elif comp_ss.get('exists'):
        score += 10
        feedback_parts.append("Completion screenshot exists but timestamp unclear.")

    # 3. VLM Verification (60 pts)
    # Use trajectory frames + any screenshots the agent took (we can't easily access agent's files directly 
    # for VLM unless we copy them, so we rely on trajectory which captures the screen anyway)
    frames = sample_trajectory_frames(traj, n=6)
    
    if not frames:
        feedback_parts.append("No trajectory frames available for VLM.")
    else:
        vlm_resp = query_vlm(prompt=VLM_PROMPT, images=frames)
        
        if vlm_resp.get("success"):
            parsed = vlm_resp.get("parsed", {})
            
            # Criterion: Correct Activity (30 pts)
            if parsed.get("correct_activity_give_change", False):
                score += 30
                feedback_parts.append("VLM: Correct 'Give Change' activity identified.")
            elif parsed.get("wrong_activity_simple_pay", False):
                feedback_parts.append("VLM: WRONG activity (Simple Pay/Count) detected.")
                # Major penalty or just 0 points here
            else:
                feedback_parts.append("VLM: Could not clearly identify activity type.")
            
            # Criterion: Progression/Completion (30 pts)
            if parsed.get("progression_observed", False):
                score += 30
                feedback_parts.append("VLM: Progression through rounds observed.")
            else:
                feedback_parts.append("VLM: No clear progression observed.")
                
        else:
            feedback_parts.append("VLM analysis failed.")

    # 4. Final Assessment
    # Pass threshold: 75 points (Needs correct activity + files or correct activity + progression + partial files)
    passed = score >= 75
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }