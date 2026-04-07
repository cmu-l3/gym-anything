#!/usr/bin/env python3
"""
Verifier for Grade Assignment Submissions task.
Checks if specific students received the correct grades and feedback comments.
"""

import json
import tempfile
import os
import logging
import math

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_grade_assignment_submissions(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_students = metadata.get('students', {})
    
    try:
        temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        try:
            copy_from_env("/tmp/grading_result.json", temp_result.name)
            with open(temp_result.name, 'r') as f:
                result = json.load(f)
        finally:
            os.unlink(temp_result.name)
            
        score = 0
        max_score = 100
        feedback_parts = []
        
        task_start = result.get('task_start_time', 0)
        expected_grader = result.get('expected_grader_id', '')
        
        # Check each student
        for username, expected in expected_students.items():
            student_res = result.get('students', {}).get(username, {})
            
            if not student_res or not student_res.get('found'):
                feedback_parts.append(f"{username}: No grade record found")
                continue
                
            # 1. Check Grade (15 pts)
            actual_grade = float(student_res.get('grade', -1.0))
            expected_grade = float(expected.get('grade', -2.0))
            
            if math.isclose(actual_grade, expected_grade, abs_tol=0.1):
                score += 15
                feedback_parts.append(f"{username}: Grade correct ({actual_grade})")
            else:
                feedback_parts.append(f"{username}: Grade incorrect (got {actual_grade}, expected {expected_grade})")
            
            # 2. Check Feedback (15 pts)
            actual_feedback = student_res.get('feedback', '')
            keywords = expected.get('feedback_keywords', [])
            keywords_found = [k for k in keywords if k.lower() in actual_feedback.lower()]
            
            if len(keywords_found) == len(keywords):
                score += 15
                feedback_parts.append(f"{username}: Feedback correct")
            elif keywords_found:
                score += 7
                feedback_parts.append(f"{username}: Feedback partial ({len(keywords_found)}/{len(keywords)} keywords)")
            else:
                feedback_parts.append(f"{username}: Feedback incorrect or missing")
                
            # 3. Check Timestamp (Anti-gaming for this student record) - implicit in total
            timemodified = int(student_res.get('timemodified', 0))
            if timemodified > task_start:
                # Giving points globally for timestamp later, but good to note
                pass
            else:
                feedback_parts.append(f"{username}: Grade modified before task start")

        # Global Anti-gaming (10 pts)
        # Check if at least one grade was modified after task start
        valid_timestamps = [
            s.get('timemodified', 0) > task_start 
            for s in result.get('students', {}).values() 
            if s and s.get('found')
        ]
        
        if any(valid_timestamps):
            score += 10
            feedback_parts.append("Grades modified during task session")
        else:
            feedback_parts.append("FAIL: No grades modified during task session")
            
        # Grader Check (Optional/Bonus, but good for anti-gaming)
        # Just ensure not graded by admin if logged in as teacher, though description implies teacher login.
        # We won't penalize heavily if correct, but nice to check.
        
        passed = score >= 85
        
        return {
            "passed": passed,
            "score": score,
            "feedback": " | ".join(feedback_parts)
        }

    except Exception as e:
        logger.error(f"Error validating grading task: {e}")
        return {"passed": False, "score": 0, "feedback": f"Validation error: {str(e)}"}