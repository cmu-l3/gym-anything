#!/usr/bin/env python3
"""
Verifier for market_research_screener_config task.

Criteria:
1. Survey exists (20 pts)
2. Question is Multiple Choice (type 'M') (10 pts)
3. Answer codes match requirements (S01-S05, NONE) (20 pts)
4. "Other" option enabled (10 pts)
5. Mandatory enabled (10 pts)
6. Randomization attribute set (15 pts)
7. Exclusion logic set for NONE (15 pts)

Pass threshold: 85 points
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_market_research_screener_config(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Copy result file
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/market_research_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback_parts = []
    
    # 1. Check Survey Existence
    if result.get('survey_found'):
        score += 20
        feedback_parts.append("Survey created")
    else:
        return {"passed": False, "score": 0, "feedback": "Survey titled 'Streaming Media Consumption' not found"}

    # 2. Check Question Type
    q_type = result.get('type', '')
    if q_type == 'M':
        score += 10
        feedback_parts.append("Question type correct (Multiple Choice)")
    else:
        feedback_parts.append(f"Wrong question type: found '{q_type}', expected 'M' (Multiple Choice)")

    # 3. Check Answer Codes
    # Expected: NONE, S01, S02, S03, S04, S05
    # The order in DB might vary, so we check for presence
    codes_str = result.get('answer_codes', '')
    if codes_str:
        codes = [c.strip() for c in codes_str.split(',')]
        required_codes = {'S01', 'S02', 'S03', 'S04', 'S05', 'NONE'}
        missing = required_codes - set(codes)
        
        if not missing:
            score += 20
            feedback_parts.append("All answer codes present")
        else:
            score += max(0, 20 - (len(missing) * 4))
            feedback_parts.append(f"Missing answer codes: {', '.join(missing)}")
    else:
        feedback_parts.append("No answer codes found")

    # 4. Check 'Other'
    if result.get('other_enabled') == 'Y':
        score += 10
        feedback_parts.append("'Other' option enabled")
    else:
        feedback_parts.append("'Other' option NOT enabled")

    # 5. Check Mandatory
    if result.get('mandatory') == 'Y':
        score += 10
        feedback_parts.append("Mandatory set")
    else:
        feedback_parts.append("Question not mandatory")

    # 6. Check Randomization
    # Value is usually '1' for enabled
    attr_random = result.get('attribute_random_order', '')
    if attr_random == '1':
        score += 15
        feedback_parts.append("Randomization enabled")
    else:
        feedback_parts.append("Randomization NOT enabled")

    # 7. Check Exclusion Logic
    # Value should be the code of the exclusive option, e.g., 'NONE'
    attr_exclusive = result.get('attribute_exclusive_option', '')
    if 'NONE' in attr_exclusive:
        score += 15
        feedback_parts.append("Exclusion logic configured correctly")
    elif attr_exclusive:
        # Partial credit if they set it but maybe to wrong code?
        score += 5
        feedback_parts.append(f"Exclusion logic set to '{attr_exclusive}' (expected 'NONE')")
    else:
        feedback_parts.append("Exclusion logic NOT configured")

    passed = score >= 85
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }