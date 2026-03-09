#!/usr/bin/env python3
"""
Verifier for create_server_alias task.
"""

import json
import tempfile
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_create_server_alias(traj, env_info, task_info):
    """
    Verify that the server alias was created with the correct settings.
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

    # Scoring details
    score = 0
    feedback_parts = []
    
    # 1. Domain Exists (25 pts)
    if result.get('domain_exists'):
        score += 25
        feedback_parts.append("Alias domain created")
    else:
        return {"passed": False, "score": 0, "feedback": "Alias domain 'acme-corp.test' was not created"}

    # 2. Is Alias of correct parent (20 pts)
    if result.get('is_alias') and result.get('parent_match'):
        score += 20
        feedback_parts.append("Correctly configured as alias of acmecorp.test")
    elif result.get('is_alias'):
        score += 10
        feedback_parts.append("Is an alias, but parent domain check failed")
    else:
        feedback_parts.append("Created as independent server, not alias")

    # 3. Web Feature (15 pts)
    # Check both Virtualmin reported state and Apache config
    if result.get('has_web') or result.get('apache_configured'):
        score += 15
        feedback_parts.append("Web feature enabled")
    else:
        feedback_parts.append("Web feature missing")

    # 4. DNS Feature (15 pts)
    if result.get('has_dns') or result.get('dns_zone_exists'):
        score += 15
        feedback_parts.append("DNS feature enabled")
    else:
        feedback_parts.append("DNS feature missing")

    # 5. Mail Feature (15 pts)
    if result.get('has_mail'):
        score += 15
        feedback_parts.append("Mail feature enabled")
    else:
        feedback_parts.append("Mail feature missing")

    # 6. Created During Task (10 pts)
    if result.get('created_during_task'):
        score += 10
    else:
        feedback_parts.append("Domain pre-existed (anti-gaming)")

    # Pass/Fail determination
    # Must have created the domain, it must be an alias, and score >= 65
    passed = result.get('domain_exists') and result.get('is_alias') and score >= 65

    return {
        "passed": passed,
        "score": score,
        "feedback": ", ".join(feedback_parts)
    }