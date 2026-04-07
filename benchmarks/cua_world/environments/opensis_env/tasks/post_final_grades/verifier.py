#!/usr/bin/env python3
import json
import os
import tempfile
import logging
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_post_final_grades(traj, env_info, task_info):
    """
    Verify that final grades were posted correctly for the 3 students.
    """
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
        return {"passed": False, "score": 0, "feedback": f"Failed to load result file: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    if 'error' in result:
        return {"passed": False, "score": 0, "feedback": f"Database query error: {result['error']}"}

    grades = result.get('grades', [])
    
    # 2. Define Expected Values
    metadata = task_info.get('metadata', {})
    expected_students = metadata.get('students', [])
    
    score = 0
    max_score = 100
    feedback = []
    
    # Helper to find student record
    def find_grade(fname, lname):
        for g in grades:
            if g['first_name'] == fname and g['last_name'] == lname:
                return g
        return None

    # 3. Verify Grades (Programmatic) - 75 points total (25 per student)
    # 4. Verify Comment (Programmatic) - 15 points
    
    all_grades_correct = True
    
    for expected in expected_students:
        fname = expected['first_name']
        lname = expected['last_name']
        
        record = find_grade(fname, lname)
        
        if not record:
            feedback.append(f"Missing record for {fname} {lname}")
            all_grades_correct = False
            continue
            
        # Check Percent
        actual_percent = float(record.get('grade_percent') or 0)
        expected_percent = float(expected['expected_percent'])
        
        # Check Letter
        actual_letter = (record.get('grade_letter') or "").strip()
        expected_letter = expected['expected_letter']
        
        student_passed = True
        
        if abs(actual_percent - expected_percent) > 0.1:
            feedback.append(f"{fname}: Wrong percent (Got {actual_percent}, Expected {expected_percent})")
            student_passed = False
            
        if actual_letter != expected_letter:
            feedback.append(f"{fname}: Wrong letter grade (Got '{actual_letter}', Expected '{expected_letter}')")
            student_passed = False
            
        # Check Comment (if expected)
        if 'expected_comment_fragment' in expected:
            actual_comment = (record.get('comment') or "").lower()
            expected_frag = expected['expected_comment_fragment'].lower()
            if expected_frag not in actual_comment:
                feedback.append(f"{fname}: Comment missing or incorrect")
                # Comment is worth 15 points separately, usually for Robert
            else:
                score += 15 # Comment correct
        
        if student_passed:
            score += 25 # Grade correct
        else:
            all_grades_correct = False

    # 5. VLM Verification (10 points)
    # Check if they actually visited the input grades screen using trajectory
    # This prevents SQL injection attacks if the agent had terminal access (which it typically doesn't, but good practice)
    frames = sample_trajectory_frames(traj, n=4)
    final_screen = get_final_screenshot(traj)
    
    vlm_prompt = """
    Analyze these screenshots of a user interacting with OpenSIS Student Information System.
    Did the user access a screen titled "Input Final Grades" or a grade entry grid?
    Look for a table with student names and input fields for "Percent", "Grade", and "Comments".
    """
    
    vlm_result = query_vlm(images=frames + [final_screen], prompt=vlm_prompt)
    
    # We are lenient with VLM here, mostly looking for UI confirmation
    if "final grades" in vlm_result.get('parsed', {}).get('response', '').lower() or \
       "grade" in vlm_result.get('parsed', {}).get('response', '').lower():
        score += 10
    else:
        # Fallback: if programmatic is perfect, give benefit of doubt
        if all_grades_correct:
            score += 10
    
    # Final cleanup
    if not all_grades_correct:
        score = min(score, 74) # Cap score if any grade is wrong (pass threshold 75)

    passed = score >= 75
    
    return {
        "passed": passed,
        "score": score,
        "feedback": "; ".join(feedback) if feedback else "All grades posted correctly."
    }