#!/usr/bin/env python3
"""
Verifier for feature_ranking_survey task.

Scoring Criteria (Total 100):
1. Survey Created & Title Match (10 pts)
2. Survey Active (10 pts)
3. 3 Question Groups (10 pts)
4. Survey Format 'Group by Group' (5 pts)
5. Text Display Question Exists (10 pts)
6. Ranking Question Exists (Type 'R') (15 pts)
   - Mandatory (5 pts)
   - At least 8 sub-questions (15 pts)
7. Numerical Input Question Exists (Type 'N') (15 pts)
   - Mandatory (5 pts)
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_feature_ranking_survey(traj, env_info, task_info):
    # Setup
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
            
    score = 0
    feedback = []
    
    # 1. Survey Exists (10 pts)
    if not result.get('survey_exists'):
        return {"passed": False, "score": 0, "feedback": "No survey found matching the task description."}
    
    score += 10
    feedback.append("Survey created found.")
    
    # 2. Survey Active (10 pts)
    if result.get('survey_active') == 'Y':
        score += 10
        feedback.append("Survey is active.")
    else:
        feedback.append("Survey is NOT active.")

    # 3. 3 Question Groups (10 pts)
    g_count = result.get('group_count', 0)
    if g_count == 3:
        score += 10
        feedback.append("Correct number of question groups (3).")
    else:
        feedback.append(f"Incorrect group count: {g_count} (Expected 3).")

    # 4. Format Group by Group (5 pts)
    # Format 'G' is group by group
    fmt = result.get('survey_format', '')
    if fmt == 'G':
        score += 5
        feedback.append("Survey format is 'Group by Group'.")
    else:
        feedback.append(f"Incorrect survey format code: {fmt} (Expected 'G').")

    # Analyze Questions
    questions = result.get('questions', [])
    subq_counts = result.get('subquestion_counts', {})
    
    has_text_display = False
    has_ranking = False
    ranking_mandatory = False
    ranking_subq_count = 0
    has_numerical = False
    numerical_mandatory = False
    
    for q in questions:
        q_type = q.get('type', '')
        q_mand = q.get('mandatory', 'N')
        q_id = str(q.get('qid'))
        
        # Text Display is type 'X'
        if q_type == 'X':
            has_text_display = True
            
        # Ranking is type 'R'
        if q_type == 'R':
            has_ranking = True
            if q_mand == 'Y':
                ranking_mandatory = True
            # Check subquestions for this QID
            ranking_subq_count = subq_counts.get(q_id, 0)
            
        # Numerical Input is type 'N'
        if q_type == 'N':
            has_numerical = True
            if q_mand == 'Y':
                numerical_mandatory = True

    # 5. Text Display (10 pts)
    if has_text_display:
        score += 10
        feedback.append("Text Display question found.")
    else:
        feedback.append("Text Display question (Type 'X') missing.")
        
    # 6. Ranking Question (Type 'R') (15 pts)
    if has_ranking:
        score += 15
        feedback.append("Ranking question found.")
        
        # Mandatory (5 pts)
        if ranking_mandatory:
            score += 5
            feedback.append("Ranking question is mandatory.")
        else:
            feedback.append("Ranking question is NOT mandatory.")
            
        # Sub-questions >= 8 (15 pts)
        if ranking_subq_count >= 8:
            score += 15
            feedback.append(f"Ranking question has {ranking_subq_count} items (Expected >= 8).")
        else:
            feedback.append(f"Ranking question has insufficient items: {ranking_subq_count} (Expected 8).")
    else:
        feedback.append("Ranking question (Type 'R') missing.")
        
    # 7. Numerical Input (Type 'N') (15 pts)
    if has_numerical:
        score += 15
        feedback.append("Numerical Input question found.")
        
        # Mandatory (5 pts)
        if numerical_mandatory:
            score += 5
            feedback.append("Numerical question is mandatory.")
        else:
            feedback.append("Numerical question is NOT mandatory.")
    else:
        feedback.append("Numerical Input question (Type 'N') missing.")

    # Final Pass Check
    # Threshold 70
    passed = score >= 70
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }