#!/usr/bin/env python3
"""
Verifier for brfss_cati_survey_config task.
Verifies the configuration of a BRFSS CATI survey in LimeSurvey.
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_brfss_cati_survey_config(traj, env_info, task_info):
    """
    Verify survey configuration.
    Criteria:
    1. Survey exists (Gatekeeper)
    2. Format = Group by Group ('G')
    3. Allow Prev = 'N'
    4. Show Progress = 'Y'
    5. Date Stamp = 'Y'
    6. Welcome text has keywords
    7. End text has keywords
    8. Enough groups (>=3)
    9. Enough questions (>=5)
    """
    
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}
        
    # Read result file
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
            
    # Gatekeeper: Survey found
    if not result.get('survey_found'):
        return {
            "passed": False, 
            "score": 0, 
            "feedback": "No survey with 'BRFSS' or 'Health Interview' in title was found."
        }
    
    settings = result.get('settings', {})
    text = result.get('text', {})
    counts = result.get('counts', {})
    metadata = task_info.get('metadata', {})
    
    score = 0
    feedback_parts = []
    
    # 1. Survey Title (Implicitly checked by export script, awarding points for existence)
    score += 10
    feedback_parts.append("Survey created")
    
    # 2. Format: Group by Group (15 pts)
    # Note: DB might store 'G', 'S' (Question by Question), 'A' (All in one)
    fmt = settings.get('format', 'S')
    if fmt == 'G':
        score += 15
        feedback_parts.append("Format: Group-by-Group (Correct)")
    else:
        feedback_parts.append(f"Format: Incorrect ('{fmt}', expected Group-by-Group)")
        
    # 3. Allow Backward Navigation: No (10 pts)
    # DB: 'N' or 'Y'
    allowprev = settings.get('allowprev', 'Y')
    if allowprev == 'N':
        score += 10
        feedback_parts.append("Backward nav: Disabled (Correct)")
    else:
        feedback_parts.append("Backward nav: Enabled (Incorrect)")

    # 4. Show Progress Bar: Yes (10 pts)
    showprogress = settings.get('showprogress', 'N')
    if showprogress == 'Y':
        score += 10
        feedback_parts.append("Progress bar: Enabled (Correct)")
    else:
        feedback_parts.append("Progress bar: Disabled (Incorrect)")
        
    # 5. Date Stamp: Yes (10 pts)
    datestamp = settings.get('datestamp', 'N')
    if datestamp == 'Y':
        score += 10
        feedback_parts.append("Date stamp: Enabled (Correct)")
    else:
        feedback_parts.append("Date stamp: Disabled (Incorrect)")
        
    # 6. Welcome Message Content (10 pts)
    welcome_text = text.get('welcome', '').lower() if text.get('welcome') else ""
    required_welcome_kw = metadata.get('welcome_keywords', ["health", "department", "random"])
    # Require at least 2 keywords
    kw_found = sum(1 for kw in required_welcome_kw if kw in welcome_text)
    if kw_found >= 2:
        score += 10
        feedback_parts.append(f"Welcome script: Good ({kw_found} keywords found)")
    else:
        feedback_parts.append(f"Welcome script: Weak (Found {kw_found} keywords, expected health/dept/random)")
        
    # 7. End Message Content (10 pts)
    end_text = text.get('end', '').lower() if text.get('end') else ""
    required_end_kw = metadata.get('end_keywords', ["thank"])
    if any(kw in end_text for kw in required_end_kw):
        score += 10
        feedback_parts.append("End script: Valid")
    else:
        feedback_parts.append("End script: Missing or invalid")
        
    # 8. Question Groups (10 pts)
    n_groups = counts.get('groups', 0)
    if n_groups >= 3:
        score += 10
        feedback_parts.append(f"Groups: {n_groups} (Correct)")
    else:
        feedback_parts.append(f"Groups: {n_groups} (Too few, expected >= 3)")
        
    # 9. Questions (15 pts)
    n_questions = counts.get('questions', 0)
    if n_questions >= 5:
        score += 15
        feedback_parts.append(f"Questions: {n_questions} (Correct)")
    else:
        feedback_parts.append(f"Questions: {n_questions} (Too few, expected >= 5)")

    # Final result
    passed = score >= 60
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }