#!/usr/bin/env python3
import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def is_active(exam_dict):
    """Determine if the exam dictionary state indicates an 'active' status."""
    if not exam_dict:
        return False
    # Check 'active' boolean/int field
    if 'active' in exam_dict:
        val = exam_dict['active']
        if val in [1, True, '1', 'true', 'True', b'\x01']:
            return True
    # Check 'status' string enum field
    if 'status' in exam_dict:
        val = str(exam_dict['status']).upper()
        if val in ['ACTIVE', '1', 'TRUE', 'PUBLISHED', 'OPEN']:
            return True
    return False

def verify_bulk_activate(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    exams = result.get('exams', {})
    error = result.get('error')
    
    # Check if we successfully got exam data from DB
    if error or not exams:
        # Fallback to VLM if database connection failed or no data exported
        try:
            from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm
            frames = sample_trajectory_frames(traj, n=3)
            final = get_final_screenshot(traj)
            
            prompt = """Analyze the UI to verify if the exams were activated correctly.
Task: Activate all 'Spring 2026' exams, EXCEPT those marked '[DEPRECATED]'. Do not modify 'Fall 2025' exams.
Return JSON with boolean fields based on the final state shown in the screenshots:
{
  "bio_active": true/false,
  "chem_active": true/false,
  "calc_active": true/false,
  "phys_inactive": true/false,
  "hist_inactive": true/false
}"""
            vlm_res = query_vlm(images=frames + [final], prompt=prompt)
            if vlm_res.get('success'):
                parsed = vlm_res.get('parsed', {})
                score = 0
                feedback = []
                if parsed.get('bio_active'): score += 20
                if parsed.get('chem_active'): score += 20
                if parsed.get('calc_active'): score += 20
                if parsed.get('phys_inactive'): score += 20
                if parsed.get('hist_inactive'): score += 20
                
                passed = score == 100
                return {"passed": passed, "score": score, "feedback": f"VLM verification used. Score: {score}/100"}
        except Exception as e:
            logger.error(f"VLM fallback failed: {e}")
            return {"passed": False, "score": 0, "feedback": "Database check failed and VLM fallback failed."}
            
    # Programmatic Database Verification
    score = 0
    feedback_parts = []
    
    # 1. Biology 101 - Positive constraint
    bio_exam = exams.get('Spring 2026: Biology 101')
    if is_active(bio_exam):
        score += 20
        feedback_parts.append("Biology 101 correctly activated")
    else:
        feedback_parts.append("Biology 101 NOT activated")

    # 2. Chemistry 201 - Positive constraint
    chem_exam = exams.get('Spring 2026: Chemistry 201')
    if is_active(chem_exam):
        score += 20
        feedback_parts.append("Chemistry 201 correctly activated")
    else:
        feedback_parts.append("Chemistry 201 NOT activated")
        
    # 3. Calculus I - Positive constraint
    calc_exam = exams.get('Spring 2026: Calculus I')
    if is_active(calc_exam):
        score += 20
        feedback_parts.append("Calculus I correctly activated")
    else:
        feedback_parts.append("Calculus I NOT activated")
        
    # 4. Physics 301 [DEPRECATED] - Negative constraint
    phys_exam = exams.get('Spring 2026: Physics 301 [DEPRECATED]')
    if phys_exam and not is_active(phys_exam):
        score += 20
        feedback_parts.append("Physics [DEPRECATED] correctly left inactive")
    elif not phys_exam:
        score += 20  # Also acceptable if they deleted it to avoid activating it
        feedback_parts.append("Physics [DEPRECATED] was deleted (acceptable)")
    else:
        feedback_parts.append("FAIL: Physics [DEPRECATED] was incorrectly activated")
        
    # 5. Fall 2025 History - Negative constraint
    hist_exam = exams.get('Fall 2025: History 101')
    if hist_exam and not is_active(hist_exam):
        score += 20
        feedback_parts.append("History 101 correctly left inactive")
    elif not hist_exam:
        score += 20  # Acceptable if deleted
        feedback_parts.append("History 101 was deleted (acceptable)")
    else:
        feedback_parts.append("FAIL: History 101 was incorrectly activated")

    passed = (score == 100)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }