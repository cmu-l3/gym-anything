#!/usr/bin/env python3
"""
Verifier for NPS Auto-Classification Survey task.

Criteria:
1. Survey exists with correct title pattern (Gate).
2. NPS Question: Code 'NPS', Type Numeric/List, Mandatory.
3. Equation Question: Type '*', Logic references NPS.
4. Follow-up Questions: 3 text questions exist.
5. Conditional Logic: Relevance equations set correctly on follow-ups.
6. Settings: Anonymized and Activated.
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_nps_survey(traj, env_info, task_info):
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
    
    # 1. Check Survey Existence (Gate)
    if not result.get('survey_found', False):
        return {
            "passed": False, 
            "score": 0, 
            "feedback": "No NPS survey found with title matching 'NPS', 'Net Promoter', or 'Customer Experience'."
        }
    
    score += 10
    feedback.append("Survey found.")
    
    survey_info = result.get('survey_info', {})
    questions = result.get('questions', [])
    
    # 2. Check NPS Question (15 pts) + Mandatory (5 pts)
    # Look for code 'NPS' (case insensitive)
    nps_q = next((q for q in questions if q['code'].upper() == 'NPS'), None)
    
    if nps_q:
        # Check type: N (numerical), L (list radio), ! (list dropdown) are acceptable
        if nps_q['type'] in ['N', 'L', '!']:
            score += 15
            feedback.append("NPS question found with valid type.")
        else:
            feedback.append(f"NPS question found but type is '{nps_q['type']}' (expected Numerical or List).")
            
        if nps_q['mandatory'] == 'Y':
            score += 5
            feedback.append("NPS question is mandatory.")
        else:
            feedback.append("NPS question is NOT mandatory.")
    else:
        feedback.append("Question with code 'NPS' not found.")

    # 3. Check Equation Question (15 pts) + Logic Content (10 pts)
    # Look for type '*' (Equation)
    eq_q = next((q for q in questions if q['type'] == '*'), None)
    
    if eq_q:
        score += 15
        feedback.append("Equation question found.")
        
        # Check logic content: must reference NPS and contain classification terms/logic
        # Logic is stored in 'text' for Equation questions in LimeSurvey
        logic_text = eq_q.get('text', '').upper()
        
        has_nps_ref = 'NPS' in logic_text or '{NPS' in logic_text
        has_logic = ('IF' in logic_text or '6' in logic_text or '7' in logic_text or '9' in logic_text)
        
        if has_nps_ref and has_logic:
            score += 10
            feedback.append("Equation logic references NPS score.")
        else:
            feedback.append("Equation text does not seem to contain valid classification logic (missing reference to NPS or thresholds).")
    else:
        feedback.append("No Equation question (type '*') found.")

    # 4. Check Follow-Up Questions (10 pts for count, 20 pts for relevance)
    # Look for text questions (Type T or S)
    text_questions = [q for q in questions if q['type'] in ['T', 'S']]
    
    if len(text_questions) >= 3:
        score += 10
        feedback.append(f"Found {len(text_questions)} text follow-up questions.")
    else:
        feedback.append(f"Found only {len(text_questions)} text questions (expected 3).")
        
    # Check Relevance
    # We expect relevance equations to be present on these questions
    # A valid relevance is not empty and not "1"
    questions_with_relevance = [q for q in questions if q.get('relevance') and q.get('relevance') != '1']
    
    if len(questions_with_relevance) >= 3:
        score += 20
        feedback.append("Relevance equations set on follow-up questions.")
    elif len(questions_with_relevance) > 0:
        score += 10
        feedback.append(f"Relevance equations set on {len(questions_with_relevance)} questions (expected 3).")
    else:
        feedback.append("No relevance equations found on questions.")

    # 5. Check Settings (Anonymized 10pts, Active 10pts)
    if survey_info.get('anonymized') == 'Y':
        score += 10
        feedback.append("Survey is anonymized.")
    else:
        feedback.append("Survey is NOT anonymized.")
        
    if survey_info.get('active') == 'Y':
        score += 5
        feedback.append("Survey is active.")
    else:
        feedback.append("Survey is NOT active.")

    passed = score >= 70
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }