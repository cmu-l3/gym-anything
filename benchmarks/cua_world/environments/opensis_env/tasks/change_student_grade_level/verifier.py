#!/usr/bin/env python3
import json
import os
import logging
import tempfile
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_change_grade_level(traj, env_info, task_info):
    """
    Verify that the agent correctly changed the student's grade level.
    
    Criteria:
    1. Student "Marcus Williams" still exists (10 pts)
    2. Grade level changed from initial (ID 1/Grade 9) (20 pts)
    3. Grade level matches target (ID 2/Grade 10) (30 pts)
    4. Enrollment is still active (not deleted/dropped) (15 pts)
    5. VLM: Validates workflow (Search -> Edit -> Save) (25 pts)
    """
    
    # 1. Setup
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System Error: Copy function unavailable"}

    metadata = task_info.get('metadata', {})
    target_grade_id = str(metadata.get('target_grade_id', '2'))
    
    # 2. Load Results from Container
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

    # 3. Evaluate Database State (75 pts total)
    score = 0
    feedback = []
    
    student_exists = result.get("student_exists", False)
    current_grade = str(result.get("enrollment", {}).get("current_grade_id", "0"))
    initial_grade = str(result.get("initial_grade_id", "1"))
    is_active = result.get("enrollment", {}).get("is_active", False)
    
    # Check 1: Student Exists (10 pts)
    if student_exists:
        score += 10
        feedback.append("Student record found.")
    else:
        feedback.append("FAIL: Student record was deleted or not found.")
        return {"passed": False, "score": 0, "feedback": "Student deleted"}

    # Check 2: Grade Changed (20 pts)
    if current_grade != initial_grade:
        score += 20
        feedback.append("Grade level was modified.")
    else:
        feedback.append(f"Grade level unchanged (Still ID {current_grade}).")

    # Check 3: Grade matches Target (30 pts)
    if current_grade == target_grade_id:
        score += 30
        feedback.append(f"Grade level correctly set to Grade 10 (ID {target_grade_id}).")
    elif current_grade != initial_grade:
        feedback.append(f"FAIL: Grade changed but to incorrect level (ID {current_grade}).")
    
    # Check 4: Enrollment Active (15 pts)
    if is_active:
        score += 15
        feedback.append("Student enrollment remains active.")
    else:
        feedback.append("FAIL: Student appears to be dropped/withdrawn (End Date set).")

    # 4. VLM Verification (25 pts)
    # Use trajectory to ensure they actually used the UI and didn't just get lucky or use a shortcut
    frames = sample_trajectory_frames(traj, n=4)
    final = get_final_screenshot(traj)
    
    if frames and final:
        vlm_prompt = (
            "Analyze these screenshots of a user using OpenSIS Student Information System. "
            "The goal is to change a student's grade level.\n"
            "Look for:\n"
            "1. A student search or student list containing 'Marcus'.\n"
            "2. A detailed student record view.\n"
            "3. An editable dropdown or field for 'Grade Level'.\n"
            "4. A success message or saved state showing 'Grade 10' or '10'.\n\n"
            "Return JSON: {\"workflow_visible\": boolean, \"grade_10_seen\": boolean, \"confidence\": float}"
        )
        
        try:
            vlm_res = query_vlm(images=frames + [final], prompt=vlm_prompt)
            parsed = vlm_res.get('parsed', {})
            
            if parsed.get('workflow_visible', False):
                score += 15
                feedback.append("VLM: Workflow logic confirmed.")
            if parsed.get('grade_10_seen', False):
                score += 10
                feedback.append("VLM: Target grade visually confirmed.")
        except Exception as e:
            logger.warning(f"VLM check failed: {e}")
            # Do not penalize score for VLM system failure if DB checks pass, 
            # but usually we want at least DB checks.
            pass

    passed = (current_grade == target_grade_id) and is_active and student_exists
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }