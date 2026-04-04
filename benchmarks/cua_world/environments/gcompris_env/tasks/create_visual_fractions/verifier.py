#!/usr/bin/env python3
"""
Verifier for create_visual_fractions task.
Verifies that the agent navigated to the correct activity, solved problems, and logged them.
"""

import json
import base64
import os
import tempfile
import logging
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_create_visual_fractions(traj, env_info, task_info):
    """
    Verify the fractions task using File checks + VLM trajectory analysis.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # 1. Retrieve exported results
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result JSON: {str(e)}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback_parts = []
    
    # ------------------------------------------------------------------
    # CHECK 1: Log File Existence and Content (25 points)
    # ------------------------------------------------------------------
    log_exists = result.get("log_exists", False)
    log_fresh = result.get("log_created_during_task", False)
    log_content_b64 = result.get("log_content_base64", "")
    
    log_lines = []
    if log_exists and log_fresh:
        try:
            log_text = base64.b64decode(log_content_b64).decode('utf-8')
            log_lines = [l.strip() for l in log_text.splitlines() if l.strip()]
            
            # Basic validation: lines should look like fractions "N/D"
            valid_fractions = [l for l in log_lines if '/' in l and l.replace('/', '').isdigit()]
            
            if len(valid_fractions) >= 3:
                score += 25
                feedback_parts.append(f"Log file valid ({len(valid_fractions)} fractions recorded)")
            elif len(valid_fractions) > 0:
                score += 15
                feedback_parts.append(f"Log file partial ({len(valid_fractions)} fractions recorded)")
            else:
                score += 5
                feedback_parts.append("Log file empty or invalid format")
        except:
            feedback_parts.append("Log file corrupt")
    else:
        feedback_parts.append("Log file missing or stale")

    # ------------------------------------------------------------------
    # CHECK 2: Agent Screenshot (15 points)
    # ------------------------------------------------------------------
    if result.get("agent_screenshot_exists", False) and result.get("agent_screenshot_created_during_task", False):
        score += 15
        feedback_parts.append("Agent screenshot created")
    else:
        feedback_parts.append("Agent screenshot missing")

    # ------------------------------------------------------------------
    # CHECK 3: VLM Trajectory Verification (60 points)
    # ------------------------------------------------------------------
    # We sample frames to verify the workflow: 
    # Menu -> Math Category -> Create Fractions Activity -> Interaction -> Success
    
    frames = sample_trajectory_frames(traj, n=6)
    final_shot = get_final_screenshot(traj)
    
    if not frames:
        return {"passed": False, "score": score, "feedback": "No trajectory frames available"}
    
    prompt = """
    Analyze these screenshots of a user interacting with GCompris educational software.
    
    I need to verify if the user performed the 'Create Fractions' activity.
    
    Look for:
    1. Navigation to the Math category (Sheep or 1,2,3 icon).
    2. The specific 'Create Fractions' interface: This typically shows a target fraction (like "1/2" or "3/4") and a visual pie chart or rectangle where segments can be filled.
    3. User interaction: The chart changing (segments filling/emptying) or the user clicking 'OK'.
    4. Success feedback: A smiley face, thumbs up, or 'Great' animation after solving a problem.
    
    Do NOT confuse this with 'Find the fraction' (which is multiple choice). This task requires CREATING the fraction visually.
    
    Return JSON:
    {
        "activity_found": boolean,
        "interaction_visible": boolean,
        "success_feedback_seen": boolean,
        "problems_solved_estimate": number,
        "fractions_seen": [list of strings like "1/2"]
    }
    """
    
    vlm_result = query_vlm(images=frames + [final_shot], prompt=prompt)
    
    if vlm_result.get("success"):
        analysis = vlm_result.get("parsed", {})
        
        # Activity Found (20 pts)
        if analysis.get("activity_found"):
            score += 20
            feedback_parts.append("Correct activity identified")
        else:
            feedback_parts.append("Target activity not seen in screenshots")
            
        # Interaction Visible (20 pts)
        if analysis.get("interaction_visible"):
            score += 20
            feedback_parts.append("User interaction detected")
            
        # Success/Progress (20 pts)
        solved_est = analysis.get("problems_solved_estimate", 0)
        success_seen = analysis.get("success_feedback_seen", False)
        
        if success_seen or solved_est >= 1:
            score += 20
            feedback_parts.append("Success feedback observed")
        elif solved_est > 0:
            score += 10
            feedback_parts.append("Partial progress observed")
            
        # Cross-reference log with VLM
        seen_fractions = analysis.get("fractions_seen", [])
        if log_lines and seen_fractions:
            matches = set(log_lines).intersection(set(seen_fractions))
            if matches:
                feedback_parts.append(f"Verified log matches screen: {', '.join(matches)}")
                
    else:
        feedback_parts.append("VLM verification failed")

    # ------------------------------------------------------------------
    # Final Scoring
    # ------------------------------------------------------------------
    passed = score >= 70
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }