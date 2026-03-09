#!/usr/bin/env python3
"""
Verifier for custom_header_auth_bypass_audit task.
"""

import json
import tempfile
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_custom_header_auth_bypass_audit(traj, env_info, task_info):
    """
    Verify that the user configured a custom header and verified it via Custom Search.
    
    Scoring:
    - Evidence File Exists & Created during task: 20 pts
    - Correct URL Crawled: 20 pts
    - Search Configuration Evident (Token in CSV): 20 pts
    - Header Injection Success (Positive match in search results): 40 pts
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

    score = 0
    feedback_parts = []
    
    # 1. File Evidence (20 pts)
    if result.get('file_exists') and result.get('file_created_during_task'):
        score += 20
        feedback_parts.append("Evidence CSV created (20/20)")
    elif result.get('file_exists'):
        score += 5
        feedback_parts.append("Evidence CSV exists but old timestamp (5/20)")
    else:
        feedback_parts.append("No evidence CSV found (0/20)")
        
    # 2. Correct URL (20 pts)
    if result.get('url_found'):
        score += 20
        feedback_parts.append("Target URL found in CSV (20/20)")
    else:
        feedback_parts.append("Target URL not found in CSV (0/20)")
        
    # 3. Token in CSV (20 pts) - Proves they set up the search rule
    if result.get('token_found_in_csv'):
        score += 20
        feedback_parts.append("Token search configuration found (20/20)")
    else:
        feedback_parts.append("Specific token not found in CSV (0/20)")
        
    # 4. Success Match (40 pts) - Proves the header was actually sent and received
    # If the search rule exists but finds 0 matches, it means the header configuration failed
    if result.get('search_match_detected'):
        score += 40
        feedback_parts.append("Header injection confirmed successful by server response (40/40)")
    else:
        feedback_parts.append("Search result negative/empty - Header likely not sent or not received (0/40)")

    passed = score >= 60
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }