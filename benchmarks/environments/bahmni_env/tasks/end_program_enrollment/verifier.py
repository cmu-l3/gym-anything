#!/usr/bin/env python3
"""
Verifier for End Program Enrollment task.
"""

import json
import logging
import os
import tempfile
from datetime import datetime
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_end_program_enrollment(traj, env_info, task_info):
    """
    Verify that the specific program enrollment was closed with today's date.
    """
    copy_from_env = env_info.get('copy_from_env')
    query_vlm = env_info.get('query_vlm')
    
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System error: copy_from_env missing"}

    # 1. Load programmatic result
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    # Check for setup failure
    if result.get("error") == "setup_failed":
        return {"passed": False, "score": 0, "feedback": "Task setup failed, cannot verify."}

    score = 0
    feedback_parts = []
    
    # Extract data
    date_completed_str = result.get("date_completed")  # Format: 2024-03-01T00:00:00.000+0000 usually
    today_str = result.get("today_date")
    program_name = result.get("program_name")
    
    # CRITERION 1: Enrollment is closed (has a completion date) [40 pts]
    if date_completed_str and date_completed_str.strip():
        score += 40
        feedback_parts.append("✅ Enrollment marked as completed")
        
        # CRITERION 2: Date is correct (Today) [30 pts]
        # Parse ISO date to YYYY-MM-DD
        try:
            # Handle standard OpenMRS date format
            completed_date_ymd = date_completed_str.split("T")[0]
            if completed_date_ymd == today_str:
                score += 30
                feedback_parts.append(f"✅ Completion date is today ({today_str})")
            else:
                feedback_parts.append(f"❌ Completion date incorrect (Expected {today_str}, got {completed_date_ymd})")
        except Exception:
            feedback_parts.append(f"❌ Could not parse date: {date_completed_str}")
    else:
        feedback_parts.append("❌ Enrollment is still active (no completion date set)")

    # CRITERION 3: Anti-gaming / Correct Target [15 pts]
    if program_name == "Wellness Tracking":
        score += 15
        feedback_parts.append("✅ Correct program modified")
    else:
        feedback_parts.append(f"❌ Wrong program modified: {program_name}")

    # CRITERION 4: VLM Trajectory Verification [15 pts]
    # Check if agent navigated to "Programs" section
    vlm_score = 0
    if query_vlm:
        frames = sample_trajectory_frames(traj, n=4)
        final_ss = get_final_screenshot(traj)
        if final_ss:
            frames.append(final_ss)
            
        prompt = """
        Analyze these screenshots of a Bahmni/OpenMRS EMR session.
        Did the user navigate to the 'Programs' section of a patient dashboard?
        Look for:
        1. A patient dashboard (Clinical view).
        2. A section or tab labeled 'Programs'.
        3. A list of enrolled programs (e.g., 'Wellness Tracking').
        4. A dialog or form to stop/close a program.
        
        Respond JSON: {"found_programs_ui": true/false, "confidence": "high/med/low"}
        """
        
        try:
            vlm_resp = query_vlm(images=frames, prompt=prompt)
            if vlm_resp.get("parsed", {}).get("found_programs_ui"):
                vlm_score = 15
                feedback_parts.append("✅ UI navigation confirmed by VLM")
            else:
                feedback_parts.append("⚠️ VLM did not clearly see Programs UI navigation")
        except Exception as e:
            logger.warning(f"VLM check failed: {e}")
            # Fallback points if programmatic pass is strong
            if score >= 70:
                vlm_score = 15
                feedback_parts.append("⚠️ (VLM skipped, assumed valid based on API state)")
    
    score += vlm_score

    passed = score >= 70
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }