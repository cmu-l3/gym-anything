#!/usr/bin/env python3
"""
Verifier for create_gradebook_assignment task.
"""

import json
import logging
import os
import tempfile

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_create_gradebook_assignment(traj, env_info, task_info):
    """
    Verifies that the gradebook category and assignment were created correctly.
    
    Criteria:
    1. Assignment Type "Projects" exists (30 pts)
    2. Assignment "Science Fair Project" exists (30 pts)
    3. Assignment is linked to the correct Type (20 pts)
    4. Points = 150 (10 pts)
    5. Due Date = 2025-06-01 (10 pts)
    """
    
    # 1. Setup and Load Data
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System Error: copy_from_env missing"}

    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result data: {str(e)}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    # 2. Extract Data
    category = result.get('category', {})
    assignment = result.get('assignment', {})
    
    category_found = result.get('category_found', False)
    assignment_found = result.get('assignment_found', False)

    # 3. Evaluate Criteria
    score = 0
    feedback = []

    # Criterion 1: Category Created (30 pts)
    if category_found and category.get('title') == 'Projects':
        score += 30
        feedback.append("Category 'Projects' created.")
    else:
        feedback.append("Category 'Projects' NOT found.")

    # Criterion 2: Assignment Created (30 pts)
    if assignment_found and assignment.get('title') == 'Science Fair Project':
        score += 30
        feedback.append("Assignment 'Science Fair Project' created.")
    else:
        feedback.append("Assignment 'Science Fair Project' NOT found.")

    # Only proceed with details if assignment exists
    if assignment_found:
        # Criterion 3: Linkage (20 pts)
        # Check if assignment's type_id matches category's id
        assign_type_id = str(assignment.get('type_id', 'A'))
        cat_id = str(category.get('id', 'B'))
        
        if category_found and assign_type_id == cat_id:
            score += 20
            feedback.append("Assignment correctly linked to Category.")
        else:
            feedback.append(f"Assignment not linked to correct category (Type ID: {assign_type_id}, Cat ID: {cat_id}).")

        # Criterion 4: Points (10 pts)
        # Database might return '150.00' or '150'
        try:
            points = float(assignment.get('points', 0))
            if points == 150.0:
                score += 10
                feedback.append("Points set correctly (150).")
            else:
                feedback.append(f"Points incorrect: {points} (expected 150).")
        except:
            feedback.append("Points value invalid.")

        # Criterion 5: Due Date (10 pts)
        due_date = str(assignment.get('due_date', ''))
        # Standardize format if needed, assuming YYYY-MM-DD from MySQL
        if '2025-06-01' in due_date:
            score += 10
            feedback.append("Due Date set correctly.")
        else:
            feedback.append(f"Due Date incorrect: {due_date} (expected 2025-06-01).")

    # 4. Final Result
    # Threshold: 80 points (Needs Category + Assignment + Linkage at minimum)
    passed = score >= 80
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }