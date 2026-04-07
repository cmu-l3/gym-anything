#!/usr/bin/env python3
"""
Verifier for post_vacancy_add_candidate task.
Verifies that:
1. A specific vacancy was created with correct details.
2. A specific candidate was created with correct details.
3. The candidate is linked to the vacancy.
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_post_vacancy_add_candidate(traj, env_info, task_info):
    """
    Verify the agent created the vacancy and candidate correctly.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load result from container
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
    feedback_parts = []
    
    # Extract data
    vacancy = result.get('vacancy', {})
    candidate = result.get('candidate', {})
    job_title_name = result.get('job_title_name', '')
    expected_hm_id = result.get('expected_hm_id', '')
    is_linked = result.get('is_linked', False)
    vacancy_increase = result.get('vacancy_count_increase', 0)
    candidate_increase = result.get('candidate_count_increase', 0)

    # 1. Verify Vacancy (40 pts)
    vacancy_exists = bool(vacancy.get('id'))
    if vacancy_exists:
        score += 15
        feedback_parts.append("Vacancy created")
        
        # Check Job Title
        if job_title_name == "HR Manager":
            score += 10
            feedback_parts.append("Job Title correct")
        else:
            feedback_parts.append(f"Incorrect Job Title ({job_title_name})")

        # Check Hiring Manager
        # Note: vacancy['hiring_manager_id'] should match expected_hm_id
        if expected_hm_id and str(vacancy.get('hiring_manager_id')) == str(expected_hm_id):
            score += 10
            feedback_parts.append("Hiring Manager correct")
        else:
            feedback_parts.append("Incorrect Hiring Manager")

        # Check Positions
        if str(vacancy.get('positions')) == "2":
            score += 5
            feedback_parts.append("Position count correct")
        else:
            feedback_parts.append(f"Incorrect positions ({vacancy.get('positions')})")
    else:
        feedback_parts.append("Vacancy NOT found")

    # 2. Verify Candidate (40 pts)
    candidate_exists = bool(candidate.get('id'))
    if candidate_exists:
        score += 15
        feedback_parts.append("Candidate created")

        # Check Name
        if candidate.get('first_name') == "Rebecca" and candidate.get('last_name') == "Martinez":
            score += 10
            feedback_parts.append("Candidate Name correct")
        else:
            feedback_parts.append("Incorrect Candidate Name")

        # Check Email
        if candidate.get('email') == "rebecca.martinez@email.com":
            score += 10
            feedback_parts.append("Candidate Email correct")
        else:
            feedback_parts.append("Incorrect Candidate Email")
            
        # Check Consent (1 = Yes)
        if str(candidate.get('consent')) == "1":
            score += 5
            feedback_parts.append("Data Consent given")
        else:
            feedback_parts.append("Data Consent missing")
    else:
        feedback_parts.append("Candidate NOT found")

    # 3. Verify Linkage (15 pts)
    if is_linked:
        score += 15
        feedback_parts.append("Candidate linked to vacancy")
    elif vacancy_exists and candidate_exists:
        feedback_parts.append("Candidate NOT linked to vacancy")
        
    # 4. Anti-gaming / Stats (5 pts)
    if vacancy_increase > 0 and candidate_increase > 0:
        score += 5
    
    # Final determination
    # Must have created both records and linked them to pass with flying colors, 
    # but we accept passing with >60 if core elements are there.
    # Essential criteria: Vacancy exists AND Candidate exists
    
    passed = (vacancy_exists and candidate_exists and score >= 60)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }