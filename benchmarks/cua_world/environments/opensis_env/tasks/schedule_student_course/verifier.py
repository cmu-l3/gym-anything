#!/usr/bin/env python3
import json
import os
import tempfile
import logging
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_schedule_student_course(traj, env_info, task_info):
    """
    Verifies if the student was scheduled into the correct course.
    
    Criteria:
    1. Database: Specific record exists linking Maria Garcia to AP Biology (30 pts).
    2. Database: Record count increased (Anti-gaming) (20 pts).
    3. VLM: Trajectory shows progression (Login -> Student Search -> Schedule) (30 pts).
    4. VLM: Final state looks correct (20 pts).
    """
    
    # 1. Setup & Data Retrieval
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System Error: copy_from_env missing"}

    # Load programmatic result
    result_data = {}
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result_data = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load task result: {str(e)}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback = []
    
    # 2. Database Verification (Primary)
    is_enrolled = result_data.get('is_enrolled_target', False)
    count_changed = result_data.get('count_changed', False)
    
    if is_enrolled:
        score += 30
        feedback.append("Success: 'AP Biology' found in Maria Garcia's schedule.")
    else:
        feedback.append("Fail: 'AP Biology' NOT found in Maria Garcia's schedule.")

    if count_changed:
        score += 20
        feedback.append("Success: New schedule record created.")
    elif is_enrolled:
        # If enrolled but count didn't change, maybe it existed (setup failure?) or swapped?
        feedback.append("Warning: Count didn't increase (record might have pre-existed).")
    else:
        feedback.append("Fail: No new records created.")

    # 3. VLM Verification (Secondary)
    # Check trajectory for workflow: Login -> Find Student -> Schedule
    frames = sample_trajectory_frames(traj, n=4)
    final_img = get_final_screenshot(traj)
    
    if not frames:
        feedback.append("Warning: No trajectory frames available for VLM.")
    else:
        prompt = (
            "Analyze these screenshots of a user using OpenSIS Student Information System.\n"
            "The goal is to enroll a student named 'Maria Garcia' into 'AP Biology'.\n"
            "Look for:\n"
            "1. Login screen or Dashboard.\n"
            "2. Student Search or Student List showing 'Maria Garcia'.\n"
            "3. A 'Schedule' or 'Scheduling' screen.\n"
            "4. Selecting 'AP Biology' or 'BIO-201'.\n"
            "5. Saving the changes.\n\n"
            "Return JSON: { \"workflow_score\": 0-30, \"evidence\": \"description\" }"
        )
        
        vlm_res = query_vlm(images=frames, prompt=prompt)
        
        if vlm_res and 'parsed' in vlm_res:
            v_score = vlm_res['parsed'].get('workflow_score', 0)
            score += min(v_score, 30)
            feedback.append(f"VLM Trajectory Analysis: {vlm_res['parsed'].get('evidence', 'No evidence')}")
        else:
            # Fallback if VLM fails
            if is_enrolled: score += 15 # Give half points if DB passed but VLM failed
            feedback.append("VLM Analysis failed or returned invalid format.")

    # 4. Final State Verification (VLM)
    if final_img:
        prompt_final = (
            "Look at this final screenshot of OpenSIS.\n"
            "Does it show a Student Schedule with 'AP Biology' or 'BIO-201' listed?\n"
            "Return JSON: { \"success\": boolean, \"confidence\": 0-10 }"
        )
        vlm_final = query_vlm(image=final_img, prompt=prompt_final)
        
        if vlm_final and 'parsed' in vlm_final:
            if vlm_final['parsed'].get('success', False):
                score += 20
                feedback.append("VLM Final Check: Schedule visible.")
    
    # 5. Final Determination
    # Pass if DB confirms enrollment AND score is decent
    passed = is_enrolled and score >= 60
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }