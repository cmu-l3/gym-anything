#!/usr/bin/env python3
"""
Verifier for live_survey_schema_update_restore@1

Criteria:
1. Survey must be Active (10 pts)
2. 'dept' question must exist with correct structure (25 pts)
3. Data must be restored (>= 15 responses) (30 pts)
4. Data integrity check (specific comment found) (25 pts)
5. Timestamps preserved (proving restoration vs manual entry) (10 pts)
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_live_survey_update(traj, env_info, task_info):
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

    # Scoring
    score = 0
    feedback = []
    
    # 1. Survey Active (10 pts)
    if result.get('is_active') == 'Y':
        score += 10
        feedback.append("Survey is active (+10)")
    else:
        feedback.append("Survey is NOT active (0)")

    # 2. Question Added (25 pts)
    # Check code, text partial match, and options count
    has_q = result.get('has_question', 0) > 0
    q_text = result.get('question_text', '').lower()
    q_opts = result.get('question_options_count', 0)
    
    if has_q:
        if 'department' in q_text:
            score += 15
            feedback.append("Question 'dept' exists with correct text (+15)")
        else:
            score += 5
            feedback.append("Question 'dept' exists but text mismatch (+5)")
            
        if q_opts >= 4:
            score += 10
            feedback.append("Question has 4+ options (+10)")
        else:
            feedback.append(f"Question has fewer options than expected ({q_opts}) (0)")
    else:
        feedback.append("Question 'dept' not found (0)")

    # 3. Data Restored Count (30 pts)
    count = int(result.get('response_count', 0))
    expected = 15
    if count >= expected:
        score += 30
        feedback.append(f"Response count restored ({count}) (+30)")
    elif count > 0:
        score += 10
        feedback.append(f"Partial data restoration ({count}/{expected}) (+10)")
    else:
        feedback.append("No response data found (0)")

    # 4. Data Integrity (25 pts)
    if result.get('verbatim_found'):
        score += 25
        feedback.append("Original text data verified (+25)")
    else:
        feedback.append("Original text data missing or corrupted (0)")

    # 5. Timestamps Preserved (10 pts)
    if result.get('timestamps_preserved'):
        score += 10
        feedback.append("Original timestamps preserved (+10)")
    else:
        if count >= expected:
            feedback.append("Timestamps indicate data was re-created/re-entered, not restored (0)")
        else:
            feedback.append("Timestamps not checked due to missing data (0)")

    # Pass Threshold
    # Must have active survey, question, and data restored to pass
    passed = (score >= 75) and (result.get('is_active') == 'Y') and (count >= expected)

    return {
        "passed": passed,
        "score": score,
        "feedback": "; ".join(feedback)
    }