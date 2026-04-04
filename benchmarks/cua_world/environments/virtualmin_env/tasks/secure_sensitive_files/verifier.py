#!/usr/bin/env python3
"""
Verifier for secure_sensitive_files task.

Verifies:
1. .env file returns 403 Forbidden (30 pts)
2. .git directory returns 403 Forbidden (30 pts)
3. Main website returns 200 OK (20 pts)
4. Sensitive files still exist on disk (10 pts)
5. Apache configuration is valid (10 pts)
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_secure_sensitive_files(traj, env_info, task_info):
    """
    Verify security hardening of sensitive files.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load result JSON
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
    
    # Check 1: Block .env (30 pts)
    code_env = result.get('http_code_env', 0)
    if code_env == 403:
        score += 30
        feedback_parts.append(".env blocked (403)")
    elif code_env == 404:
        # Penalize slightly if they deleted it, but existence check handles that too
        feedback_parts.append(".env not found (404) - should be forbidden")
    else:
        feedback_parts.append(f".env accessible ({code_env})")

    # Check 2: Block .git (30 pts)
    code_git = result.get('http_code_git', 0)
    if code_git == 403:
        score += 30
        feedback_parts.append(".git blocked (403)")
    elif code_git == 404:
        feedback_parts.append(".git not found (404) - should be forbidden")
    else:
        feedback_parts.append(f".git accessible ({code_git})")

    # Check 3: Site Availability (20 pts)
    code_home = result.get('http_code_home', 0)
    if code_home == 200:
        score += 20
        feedback_parts.append("Site active")
    else:
        feedback_parts.append(f"Site down ({code_home})")

    # Check 4: Files Preserved (10 pts)
    if result.get('files_exist_on_disk', False):
        score += 10
        feedback_parts.append("Files preserved")
    else:
        feedback_parts.append("Files deleted (Anti-gaming penalty)")

    # Check 5: Config Valid (10 pts)
    if result.get('apache_config_valid', False):
        score += 10
        feedback_parts.append("Config valid")
    else:
        feedback_parts.append("Apache config error")

    # Determine pass/fail
    # Must block both targets and keep site up to pass
    passed = (code_env == 403) and (code_git == 403) and (code_home == 200)

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }