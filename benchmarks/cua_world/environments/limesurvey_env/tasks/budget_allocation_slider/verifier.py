#!/usr/bin/env python3
"""
Verifier for Participatory Budgeting Slider Task.
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_budget_allocation_slider(traj, env_info, task_info):
    """
    Verifies the configuration of the budget slider survey.
    
    Criteria:
    1. Survey exists with correct title.
    2. BUDGET question is Type K (Multiple Numerical).
    3. BUDGET question has slider_layout=1 and equals_num_value=100.
    4. Sub-questions SAFE, INFRA, PARK, HLTH, GOV exist.
    5. REASON question exists.
    6. REASON relevance equation checks INFRA > 40.
    7. Survey is active.
    """
    
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load result
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/budget_task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback = []
    
    # Check 1: Survey Found (Gate)
    if not result.get('survey_found'):
        return {"passed": False, "score": 0, "feedback": "Survey 'Springfield 2026 Budget Consultation' not found."}
    
    score += 5
    feedback.append("Survey created.")

    # Check 2: Active (10 pts)
    if result.get('active') == 'Y':
        score += 10
        feedback.append("Survey is active.")
    else:
        feedback.append("Survey is NOT active.")

    # Check 3: Budget Question Type (10 pts)
    # Type 'K' is Multiple Numerical Input
    bq = result.get('budget_question', {})
    if bq.get('found'):
        if bq.get('type') == 'K':
            score += 10
            feedback.append("BUDGET question type correct.")
        else:
            feedback.append(f"BUDGET question type incorrect (Expected 'K', got '{bq.get('type')}').")
            
        # Check 4: Slider Configuration (20 pts)
        # slider_layout should be '1' (or 'Y' depending on version, usually 1 in DB)
        if str(bq.get('slider_layout')) in ['1', 'Y', 'true']:
            score += 10
            feedback.append("Slider layout enabled.")
        else:
            feedback.append("Slider layout NOT enabled.")
            
        # Check 5: Sum Constraint (15 pts)
        if str(bq.get('equals_sum_value')) == '100':
            score += 15
            feedback.append("Sum constraint set to 100.")
        else:
            feedback.append(f"Sum constraint incorrect (Expected 100, got '{bq.get('equals_sum_value')}').")
            
        # Check 6: Sub-questions (15 pts)
        subs = bq.get('sub_questions', [])
        expected_subs = ["SAFE", "INFRA", "PARK", "HLTH", "GOV"]
        # Check intersection
        found_subs = [s for s in subs if s in expected_subs]
        if len(found_subs) == 5:
            score += 15
            feedback.append("All 5 sub-questions found.")
        elif len(found_subs) >= 3:
            score += 7
            feedback.append(f"Some sub-questions missing (Found {len(found_subs)}/5).")
        else:
            feedback.append("Sub-questions missing or incorrect codes.")
    else:
        feedback.append("BUDGET question not found.")

    # Check 7: Reason Question & Logic (15 pts)
    rq = result.get('reason_question', {})
    if rq.get('found'):
        relevance = rq.get('relevance', '')
        # Logic check: needs 'INFRA' (or BUDGET_INFRA), '>', and '40'
        # Can be "BUDGET_INFRA > 40" or "((BUDGET_INFRA.NAOK > 40))" etc.
        if ('INFRA' in relevance) and ('>' in relevance or 'gt' in relevance.lower()) and ('40' in relevance):
            score += 15
            feedback.append("Relevance logic correct.")
        else:
            feedback.append(f"Relevance logic incorrect or missing (Found: '{relevance}').")
    else:
        feedback.append("REASON question not found.")

    return {
        "passed": score >= 70,
        "score": score,
        "feedback": " | ".join(feedback)
    }