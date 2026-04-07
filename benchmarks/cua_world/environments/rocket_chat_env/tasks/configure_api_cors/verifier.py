#!/usr/bin/env python3
"""
Verifier for configure_api_cors task.

This verifier evaluates if the agent successfully enabled API CORS and whitelisted
the two specific domains in Rocket.Chat's Administration settings.

Criteria:
1. CORS Enabled (API_Enable_CORS is true) - 40 points
2. HR Dashboard domain present in origins - 25 points
3. Intranet domain present in origins - 25 points
4. No wildcard ('*') present, strictly limiting origins - 10 points
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_configure_api_cors(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_domains = metadata.get('target_domains', [
        "https://hr-dashboard.internal",
        "https://intranet.mobile.corp"
    ])

    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read exported result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    logger.info(f"Task Result JSON: {result}")

    score = 0
    feedback_parts = []
    
    # 1. Check if CORS is enabled
    cors_enabled = result.get('cors_enabled', False)
    if str(cors_enabled).lower() == 'true':
        score += 40
        feedback_parts.append("CORS successfully enabled (+40)")
    else:
        feedback_parts.append("CORS is NOT enabled")

    # 2 & 3. Check origins list
    cors_origin_str = result.get('cors_origin', '')
    # Clean the string: split by comma, strip whitespace, remove trailing slashes for robust matching
    origins_list = [domain.strip().rstrip('/') for domain in cors_origin_str.split(',') if domain.strip()]
    
    logger.info(f"Parsed origins list: {origins_list}")
    
    domain_1 = expected_domains[0].rstrip('/')
    domain_2 = expected_domains[1].rstrip('/')
    
    found_domain_1 = domain_1 in origins_list
    found_domain_2 = domain_2 in origins_list

    if found_domain_1:
        score += 25
        feedback_parts.append(f"HR Dashboard domain found (+25)")
    else:
        feedback_parts.append(f"Missing HR Dashboard domain '{domain_1}'")
        
    if found_domain_2:
        score += 25
        feedback_parts.append(f"Intranet domain found (+25)")
    else:
        feedback_parts.append(f"Missing Intranet domain '{domain_2}'")

    # 4. Check that wildcard (*) is NOT present (strict whitelist constraint)
    if '*' in origins_list:
        feedback_parts.append("Security failure: Wildcard ('*') is present in the origins list")
    elif len(origins_list) == 0:
        feedback_parts.append("Origins list is empty")
    else:
        score += 10
        feedback_parts.append("Origins list strictly configured without wildcard (+10)")

    # Construct final outcome
    passed = (score == 100)
    feedback = " | ".join(feedback_parts)

    return {
        "passed": passed,
        "score": score,
        "feedback": feedback
    }