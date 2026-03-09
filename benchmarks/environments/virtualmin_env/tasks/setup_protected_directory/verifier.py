#!/usr/bin/env python3
"""
Verifier for setup_protected_directory task.

Verifies:
1. HTTP 401 response for unauthenticated requests
2. HTTP 200 response for authenticated requests (with correct content)
3. HTTP 401 response for wrong credentials (ensures auth is actually checking password)
4. Existence of configuration artifacts (.htaccess/.htpasswd or Apache config)
5. Anti-gaming (timestamps, initial state check)
"""

import json
import os
import tempfile
import logging
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_setup_protected_directory(traj, env_info, task_info):
    """
    Verify the password protection setup.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Retrieve result JSON from container
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result JSON: {str(e)}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback_parts = []
    
    task_start = result.get('task_start', 0)
    initial_state = result.get('initial_state', 'unknown')

    # ---------------------------------------------------------
    # Criterion 1: Configuration Existence (40 pts)
    # ---------------------------------------------------------
    config_score = 0
    
    # Check for Auth Config (.htaccess or Apache Directory block)
    has_auth_config = result.get('htaccess_exists', False) or result.get('apache_config_has_auth', False)
    
    # Check for Password File with User
    has_user = result.get('reviewer_user_found', False)
    
    if has_auth_config:
        config_score += 20
        feedback_parts.append("Auth configuration found")
    else:
        feedback_parts.append("No auth configuration found")
        
    if has_user:
        config_score += 20
        feedback_parts.append("User 'reviewer' found in password file")
    else:
        feedback_parts.append("User 'reviewer' NOT found")
        
    # Timestamp check for anti-gaming
    htaccess_mtime = result.get('htaccess_mtime', 0)
    passwd_mtime = result.get('passwd_file_mtime', 0)
    
    if has_auth_config and result.get('htaccess_exists', False) and htaccess_mtime < task_start:
        config_score -= 10
        feedback_parts.append("Warning: .htaccess predates task start")
        
    score += config_score

    # ---------------------------------------------------------
    # Criterion 2: Functional Protection (60 pts)
    # ---------------------------------------------------------
    func_score = 0
    
    http_no = str(result.get('http_no_auth', '000'))
    http_wrong = str(result.get('http_wrong_auth', '000'))
    http_correct = str(result.get('http_correct_auth', '000'))
    content_match = result.get('content_match', False)
    
    # Case A: No Auth -> 401 (20 pts)
    if http_no == "401":
        func_score += 20
        feedback_parts.append("Correctly blocked unauthenticated access (401)")
    elif http_no == "403":
        func_score += 10
        feedback_parts.append("Partial: Access forbidden (403) but expected 401")
    elif http_no == "200":
        feedback_parts.append("FAIL: Directory is still accessible without password")
    else:
        feedback_parts.append(f"Unexpected status for no-auth: {http_no}")
        
    # Case B: Correct Auth -> 200 (25 pts)
    if http_correct == "200":
        if content_match:
            func_score += 25
            feedback_parts.append("Correct credentials work and serve content")
        else:
            func_score += 20
            feedback_parts.append("Correct credentials work but content mismatch")
    elif http_correct == "401":
        feedback_parts.append("FAIL: Correct credentials were rejected (401)")
    else:
        feedback_parts.append(f"Unexpected status for correct auth: {http_correct}")

    # Case C: Wrong Auth -> 401 (15 pts)
    if http_wrong == "401":
        func_score += 15
        feedback_parts.append("Wrong credentials correctly rejected (401)")
    elif http_wrong == "200":
        func_score = 0 # Critical fail if wrong password works
        feedback_parts.append("CRITICAL FAIL: Wrong password allowed access!")
    
    score += func_score

    # ---------------------------------------------------------
    # VLM Verification (Optional sanity check)
    # ---------------------------------------------------------
    # We mainly rely on programmatic checks here, but we can look for
    # visual confirmation if programmatic checks are ambiguous.
    # For this task, programmatic checks are definitive.
    
    final_score = min(100, max(0, score))
    passed = final_score >= 60 and http_correct == "200" and http_no == "401"
    
    return {
        "passed": passed,
        "score": final_score,
        "feedback": " | ".join(feedback_parts)
    }