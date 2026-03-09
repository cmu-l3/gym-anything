#!/usr/bin/env python3
"""
Verifier for Bulk Mandatory Update task.

Criteria:
1. Questions Q1-Q9 must be Mandatory ('Y').
2. Question Q10 must be Optional ('N').
3. Survey must be Active ('Y').
4. Data Integrity:
   - Question count must match initial (no deletions).
   - Q1 text must match original (no recreation with wrong text).
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_bulk_mandatory_update(traj, env_info, task_info):
    # Setup
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    target_mandatory = metadata.get('target_mandatory_questions', [])
    target_optional = metadata.get('target_optional_questions', [])
    integrity_text = metadata.get('integrity_check_text_fragment', "belong to this community")

    # Read result
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
    max_score = 100
    feedback_parts = []
    
    # Check 1: Mandatory Questions (45 points)
    # 5 points per correct mandatory question
    q_statuses = result.get('question_statuses', {})
    mandatory_correct_count = 0
    
    for q_code in target_mandatory:
        status = q_statuses.get(q_code, 'Unknown')
        if status == 'Y':
            mandatory_correct_count += 1
        else:
            feedback_parts.append(f"{q_code} is NOT mandatory (found '{status}')")
            
    mandatory_score = mandatory_correct_count * 5
    score += mandatory_score
    if mandatory_correct_count == len(target_mandatory):
        feedback_parts.append(f"All {len(target_mandatory)} scale questions set to Mandatory [45/45]")
    else:
        feedback_parts.append(f"{mandatory_correct_count}/{len(target_mandatory)} questions set to Mandatory [{mandatory_score}/45]")

    # Check 2: Optional Question Q10 (15 points)
    q10_status = q_statuses.get('Q10', 'Unknown')
    if q10_status == 'N':
        score += 15
        feedback_parts.append("Comment question (Q10) correctly kept Optional [15/15]")
    else:
        feedback_parts.append(f"Comment question (Q10) was incorrectly set to Mandatory [0/15]")

    # Check 3: Survey Activation (30 points)
    active_status = result.get('survey_active', 'N')
    if active_status == 'Y':
        score += 30
        feedback_parts.append("Survey successfully activated [30/30]")
    else:
        feedback_parts.append("Survey is NOT active [0/30]")

    # Check 4: Data Integrity (10 points)
    integrity_score = 0
    # Subcheck: Count matches
    initial_count = int(result.get('initial_q_count', 0))
    final_count = int(result.get('final_q_count', 0))
    
    # Subcheck: Text matches
    q1_text = result.get('q1_text', '')
    
    if initial_count > 0 and final_count == initial_count and integrity_text in q1_text:
        integrity_score = 10
        feedback_parts.append("Data integrity verified (no questions deleted/altered) [10/10]")
    else:
        if final_count != initial_count:
            feedback_parts.append(f"Integrity warning: Question count changed ({initial_count}->{final_count})")
        if integrity_text not in q1_text:
            feedback_parts.append("Integrity warning: Question text modified or deleted")
    
    score += integrity_score

    # Final Result
    passed = score >= 80
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }