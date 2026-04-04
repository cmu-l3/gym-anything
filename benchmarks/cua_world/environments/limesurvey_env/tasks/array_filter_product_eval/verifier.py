#!/usr/bin/env python3
import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_array_filter_task(traj, env_info, task_info):
    """
    Verify the Streaming Services survey with array_filter logic.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Copy result file
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

    if not result.get('survey_found'):
        return {
            "passed": False, 
            "score": 0, 
            "feedback": "Survey titled 'Streaming Services Consumer Evaluation' not found."
        }

    score = 0
    feedback = []

    # 1. Survey Exists (Gate passed)
    score += 10
    feedback.append("Survey found.")

    # 2. Survey Settings: Active & Anonymous
    info = result.get('survey_info', {})
    if info.get('active') == 'Y':
        score += 10
        feedback.append("Survey is active.")
    else:
        feedback.append("Survey is NOT active.")

    if info.get('anonymized') == 'Y':
        score += 10
        feedback.append("Survey is anonymous.")
    else:
        feedback.append("Survey is NOT anonymous.")

    # 3. Structure: 3 Groups
    group_count = int(result.get('group_count', 0))
    if group_count >= 3:
        score += 10
        feedback.append(f"Correct number of groups ({group_count}).")
    else:
        feedback.append(f"Insufficient groups found ({group_count}/3).")

    # 4. Questions Analysis
    questions = result.get('questions', [])
    attributes = result.get('attributes', [])

    # Find the Multiple Choice (M) question
    mc_questions = [q for q in questions if q['type'] == 'M' and q['parent_qid'] == '0']
    mc_question = mc_questions[0] if mc_questions else None

    if mc_question:
        score += 10
        feedback.append(f"Multiple Choice question found (Code: {mc_question['code']}).")
        
        # Check subquestions for MC
        mc_subs = [q for q in questions if q['parent_qid'] == mc_question['qid']]
        if len(mc_subs) >= 7:
            score += 10
            feedback.append(f"MC question has {len(mc_subs)} options (>=7).")
        else:
            feedback.append(f"MC question has insufficient options ({len(mc_subs)}/7).")
    else:
        feedback.append("Multiple Choice question NOT found.")

    # Find Array (F) questions
    # Type 'F' is Array (5 point choice). Sometimes 'H' (Array by column) is used, but spec asked for F.
    # We'll accept F or H to be lenient on visual layout choice, but spec implied F.
    array_questions = [q for q in questions if q['type'] in ['F', 'H'] and q['parent_qid'] == '0']
    
    if len(array_questions) >= 2:
        score += 10
        feedback.append(f"Found {len(array_questions)} Array questions.")
    else:
        feedback.append(f"Found only {len(array_questions)} Array questions (expected 2).")

    # 5. Check array_filter Attribute
    # The attribute value must match the MC question code
    filter_correct_count = 0
    
    if mc_question and array_questions:
        mc_code = mc_question['code']
        
        for aq in array_questions:
            # Look for array_filter attribute for this question
            attrs = [a for a in attributes if a['qid'] == aq['qid'] and a['attribute'] == 'array_filter']
            
            if attrs:
                val = attrs[0]['value']
                if val == mc_code:
                    filter_correct_count += 1
                else:
                    feedback.append(f"Array question {aq['code']} has wrong filter value '{val}' (expected '{mc_code}').")
            else:
                feedback.append(f"Array question {aq['code']} missing 'array_filter' attribute.")

    # Scoring for filters (15 pts each for the two required array questions)
    if filter_correct_count >= 2:
        score += 30
        feedback.append("Both array questions correctly filtered by MC question.")
    elif filter_correct_count == 1:
        score += 15
        feedback.append("One array question correctly filtered.")
    else:
        feedback.append("No array questions correctly filtered.")

    passed = score >= 70
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }