#!/usr/bin/env python3
"""
Verifier for Panel Integration & Screenout Redirection Task.

Verifies:
1. URL Parameter 'rid' exists
2. Survey End URL is correctly formatted with passthru
3. Screenout Quota exists (limit 0) on correct question
4. Screenout URL is correctly formatted with passthru
"""

import json
import tempfile
import os
import logging
from urllib.parse import urlparse, parse_qs

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_panel_config(traj, env_info, task_info):
    # 1. Setup & Read Data
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
    
    # Metadata targets
    metadata = task_info.get('metadata', {})
    target_base_complete = metadata.get('success_url_base', 'https://api.techsample.com/complete')
    target_base_term = metadata.get('term_url_base', 'https://api.techsample.com/term')
    
    # --- Criterion 1: URL Parameter (25 pts) ---
    if result.get('param_exists'):
        score += 25
        feedback.append("URL parameter 'rid' configured correctly.")
    else:
        feedback.append("Missing URL parameter 'rid'.")

    # --- Criterion 2: Success Redirect (25 pts) ---
    end_url = result.get('end_url', '')
    auto_red = result.get('auto_redirect', 'N')
    
    url_correct = False
    if target_base_complete in end_url and "{PASSTHRU:rid}" in end_url:
        url_correct = True
    
    if url_correct and auto_red == 'Y':
        score += 25
        feedback.append("Success redirect URL and auto-load configured correctly.")
    elif url_correct:
        score += 15
        feedback.append("Success redirect URL correct, but auto-load NOT enabled.")
    elif auto_red == 'Y':
        score += 5
        feedback.append("Auto-load enabled, but Success URL format is incorrect.")
    else:
        feedback.append("Success redirect not configured correctly.")

    # --- Criterion 3: Quota Logic (25 pts) ---
    quota_found = result.get('quota_found')
    q_limit = result.get('quota_limit')
    q_code = result.get('quota_member_code') # Should be 'N' for No (or A2 depending on internal code)
    
    # Limesurvey 'Y'/'N' question type usually stores answers as 'Y' and 'N'
    if quota_found and str(q_limit) == '0' and (q_code == 'N' or q_code == 'A2' or q_code == '0'):
        score += 25
        feedback.append("Screenout quota configured correctly (Limit 0 on 'No').")
    elif quota_found:
        score += 10
        feedback.append(f"Quota found but configuration issues (Limit: {q_limit}, Code: {q_code}).")
    else:
        feedback.append("No screenout quota found.")

    # --- Criterion 4: Screenout URL (25 pts) ---
    q_url = result.get('quota_url', '')
    q_autoload = result.get('quota_autoload') # 1 for Yes, 0 for No usually in DB
    
    term_url_correct = False
    if target_base_term in q_url and "{PASSTHRU:rid}" in q_url:
        term_url_correct = True
        
    # Autoload in quota languagesettings is often integer 1/0
    autoload_correct = str(q_autoload) == '1'
    
    if term_url_correct and autoload_correct:
        score += 25
        feedback.append("Screenout URL and auto-load configured correctly.")
    elif term_url_correct:
        score += 15
        feedback.append("Screenout URL correct, but auto-load NOT enabled.")
    else:
        feedback.append("Screenout URL configuration failed.")

    return {
        "passed": score >= 75,
        "score": score,
        "feedback": " | ".join(feedback)
    }