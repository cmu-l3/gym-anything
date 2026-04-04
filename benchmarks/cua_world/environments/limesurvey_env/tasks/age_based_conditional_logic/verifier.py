#!/usr/bin/env python3
"""
Verifier for Age-Based Conditional Logic Task

Checks:
1. Survey existence and activation
2. DOB Question configuration
3. Age Calculation Equation logic
4. Group Relevance logic (18 <= Age <= 65)
5. Medical History group content
"""

import json
import os
import tempfile
import logging
import re

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_age_logic(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load result
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

    score = 0
    feedback = []
    
    # 1. Survey Existence (Gate)
    if not result.get('survey_found'):
        return {
            "passed": False, 
            "score": 0, 
            "feedback": "Survey not found. Ensure title contains 'Influenza' or 'Vaccine'."
        }
    
    score += 10
    feedback.append("Survey created")

    # 2. DOB Question (20 pts)
    if result.get('dob_question_exists'):
        score += 20
        feedback.append("DOB question (Type: Date) found")
    else:
        feedback.append("DOB question missing or incorrect type/code")

    # 3. Age Calculation Equation (30 pts)
    # We check if it exists AND contains necessary components (DOB reference + math)
    calc_exists = result.get('calc_question_exists')
    calc_eq = result.get('calc_equation', '').replace(' ', '').lower()
    
    if calc_exists:
        # Check logic: needs to reference DOB and do some date math
        # Common patterns: (strtotime("now")-strtotime(DOB))/31557600 or date("Y")-date("Y",strtotime(DOB))
        has_dob_ref = 'dob' in calc_eq
        has_date_math = ('date' in calc_eq or 'strtotime' in calc_eq) and ('-' in calc_eq or '/' in calc_eq)
        
        if has_dob_ref and has_date_math:
            score += 30
            feedback.append("Age calculation equation valid")
        else:
            score += 15
            feedback.append("Age calculation question exists but logic seems incomplete")
    else:
        feedback.append("Age calculation equation missing")

    # 4. Group Relevance (30 pts)
    # Check if a group exists with relevance logic for 18-65
    groups = result.get('groups', [])
    medical_group_found = False
    relevance_correct = False
    
    if len(groups) >= 2:
        # Assuming second group is Medical History, but we check all groups after the first
        for group in groups:
            # Skip first group (Demographics)
            if group.get('group_order', 0) == 0:
                continue
                
            g_relevance = str(group.get('grelevance', '')).replace(' ', '').lower()
            
            # Check for bounds: 18 and 65
            has_lower = '18' in g_relevance and ('>' in g_relevance or 'ge' in g_relevance)
            has_upper = '65' in g_relevance and ('<' in g_relevance or 'le' in g_relevance)
            has_var = 'age_calc' in g_relevance
            
            if has_var and has_lower and has_upper:
                relevance_correct = True
                medical_group_found = True
                
                # Check for questions in this group
                q_count = group.get('question_count', 0)
                if q_count >= 3:
                    score += 10 # Bonus for content
                    feedback.append(f"Medical group has {q_count} questions")
                break
    
    if relevance_correct:
        score += 30
        feedback.append("Group relevance logic correct (18-65)")
    else:
        feedback.append("Group relevance logic missing or incorrect")

    # 5. Survey Active (10 pts)
    if result.get('active') == 'Y':
        score += 10
        feedback.append("Survey is active")
    else:
        feedback.append("Survey is not active")

    return {
        "passed": score >= 70,
        "score": score,
        "feedback": " | ".join(feedback)
    }