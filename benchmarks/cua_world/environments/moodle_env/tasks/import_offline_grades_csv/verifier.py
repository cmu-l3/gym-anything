#!/usr/bin/env python3
"""Verifier for Import Offline Grades CSV task."""

import json
import tempfile
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_import_offline_grades(traj, env_info, task_info):
    """
    Verify that grades were imported correctly into the specified item.
    
    Criteria:
    1. Grades recorded for all 3 students (10 pts)
    2. Grades match expected values (30 pts each)
    3. Grades are in the CORRECT existing item, not a new one (Critical for full points)
    
    We deduct points if a new item was created instead of mapping to the existing one.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Expected values
    expected = {
        "jsmith": 85.0,
        "mjones": 92.0,
        "awilson": 78.0
    }
    
    try:
        temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        try:
            copy_from_env("/tmp/import_grades_result.json", temp_result.name)
            with open(temp_result.name, 'r') as f:
                result = json.load(f)
        finally:
            os.unlink(temp_result.name)
            
        score = 0
        feedback_parts = []
        
        target_item_id = result.get('target_item_id', 0)
        students = result.get('students', {})
        created_item_name = result.get('created_item_name', '')
        
        # Check specific student grades
        correct_values = 0
        correct_mapping = 0
        
        for user, expected_val in expected.items():
            data = students.get(user, {})
            grade = float(data.get('grade', 0))
            item_id = int(data.get('item_id', 0))
            
            # Check value match (tolerance 0.1)
            if abs(grade - expected_val) < 0.1:
                correct_values += 1
                
                # Check mapping (must match target_item_id)
                if item_id == target_item_id and item_id != 0:
                    correct_mapping += 1
            else:
                logger.info(f"{user}: Expected {expected_val}, got {grade}")

        # Scoring Logic
        
        # 1. Activity detected (10 pts)
        if correct_values > 0:
            score += 10
            feedback_parts.append("Import attempted")
        else:
            return {"passed": False, "score": 0, "feedback": "No grades imported correctly"}
            
        # 2. Value correctness (90 pts distributed)
        # 30 pts per student: 15 for value, 15 for correct mapping
        
        for user in expected:
            data = students.get(user, {})
            grade = float(data.get('grade', 0))
            item_id = int(data.get('item_id', 0))
            expected_val = expected[user]
            
            user_score = 0
            user_feedback = []
            
            # Value check
            if abs(grade - expected_val) < 0.1:
                user_score += 15
                user_feedback.append("Value OK")
                
                # Mapping check
                if item_id == target_item_id:
                    user_score += 15
                    user_feedback.append("Mapping OK")
                elif item_id != 0:
                    user_feedback.append(f"Wrong Item (created '{created_item_name}'?)")
            else:
                user_feedback.append(f"Value Mismatch ({grade} vs {expected_val})")
                
            score += user_score
            # feedback_parts.append(f"{user}: {', '.join(user_feedback)}")

        # General feedback on mapping
        if correct_values == 3 and correct_mapping == 0:
            feedback_parts.append("CRITICAL: You created a NEW grade item instead of mapping to the existing 'Lab Practical 1'. Check the mapping settings.")
        elif correct_mapping == 3:
            feedback_parts.append("All grades imported and mapped correctly.")
        else:
            feedback_parts.append(f"Correct values: {correct_values}/3. Correct mapping: {correct_mapping}/3.")

        passed = (score >= 100)
        
        return {
            "passed": passed,
            "score": score,
            "feedback": " | ".join(feedback_parts)
        }
        
    except Exception as e:
        logger.error(f"Error verification: {e}")
        return {"passed": False, "score": 0, "feedback": f"Verification error: {str(e)}"}