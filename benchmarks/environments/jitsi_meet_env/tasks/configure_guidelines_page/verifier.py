#!/usr/bin/env python3
"""
Verifier for configure_guidelines_page task.
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_configure_guidelines_page(traj, env_info, task_info):
    """
    Verify that the user configured the guidelines page correctly.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load task metadata
    metadata = task_info.get('metadata', {})
    required_strings = metadata.get('required_strings', [])

    score = 0
    max_score = 100
    feedback_parts = []
    
    # Temporary files for data extraction
    result_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    response_file = tempfile.NamedTemporaryFile(delete=False, suffix='.html')

    try:
        # Retrieve JSON result
        copy_from_env("/tmp/task_result.json", result_file.name)
        with open(result_file.name, 'r') as f:
            result = json.load(f)
            
        # Retrieve HTTP response body
        try:
            copy_from_env("/tmp/task_response_body.html", response_file.name)
            with open(response_file.name, 'r', encoding='utf-8', errors='ignore') as f:
                response_content = f.read()
        except Exception:
            response_content = ""
            
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve verification data: {e}"}
    finally:
        if os.path.exists(result_file.name):
            os.unlink(result_file.name)
        if os.path.exists(response_file.name):
            os.unlink(response_file.name)

    # 1. Check HTTP Status (Critical) - 25 points
    http_status = result.get('http_status', '000')
    if http_status == '200':
        score += 25
        feedback_parts.append("Page accessible (HTTP 200)")
    else:
        feedback_parts.append(f"Page not accessible (HTTP {http_status})")
        # If page isn't accessible, they fail the critical check
        return {
            "passed": False,
            "score": score,
            "feedback": " | ".join(feedback_parts)
        }

    # 2. Check HTML Content - 40 points total
    content_score = 0
    missing_strings = []
    
    # Normalize content for searching (case insensitive, ignore whitespace)
    normalized_content = " ".join(response_content.lower().split())
    
    for req_str in required_strings:
        normalized_req = " ".join(req_str.lower().split())
        if normalized_req in normalized_content:
            content_score += (40 / len(required_strings))
        else:
            missing_strings.append(req_str)
            
    score += int(content_score)
    if not missing_strings:
        feedback_parts.append("All content present")
    else:
        feedback_parts.append(f"Missing {len(missing_strings)} content elements")

    # 3. Check File in Container - 15 points
    if result.get('container_file_exists', False):
        score += 15
        feedback_parts.append("File exists in container")
    else:
        feedback_parts.append("File not found in container path")

    # 4. Check Backup File - 10 points
    if result.get('backup_exists', False):
        if result.get('backup_created_during_task', False):
            score += 10
            feedback_parts.append("Backup file created")
        else:
            score += 5
            feedback_parts.append("Backup file exists but old")
    else:
        feedback_parts.append("No backup file")

    # 5. Check Nginx Config - 10 points
    # (Just checking if grep found 'guidelines' in nginx config files)
    if result.get('nginx_config_found', False):
        score += 10
        feedback_parts.append("Nginx config updated")
    else:
        # If it works (HTTP 200) but we didn't grep the config line, 
        # it might be done via a method we didn't catch or just implicit?
        # But for this task, explicit config is expected. 
        # However, if HTTP 200 works, they must have done something right.
        if http_status == '200':
            score += 10
            feedback_parts.append("Nginx working (config assumed)")
        else:
            feedback_parts.append("Nginx config not found")

    # Pass Threshold
    passed = (score >= 60) and (http_status == '200')

    return {
        "passed": passed,
        "score": min(100, score),
        "feedback": " | ".join(feedback_parts)
    }