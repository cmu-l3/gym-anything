#!/usr/bin/env python3
"""
Verifier for implement_authorized_ssh_whitelist task.
Verifies CDB list creation, configuration, and rule logic via functional testing.
"""

import json
import tempfile
import os
import logging
import re

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_implement_authorized_ssh_whitelist(traj, env_info, task_info):
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
    
    # Extract data
    config_content = result.get("config_content", {})
    list_content = config_content.get("list_content", "")
    ossec_conf = config_content.get("ossec_conf", "")
    local_rules = config_content.get("local_rules", "")
    functional = result.get("functional_test", {})
    
    # Criteria 1: List Creation (20 pts)
    # Check if list file exists and contains 'ga'
    # Format should be 'ga:' or just 'ga' (Wazuh 4.x is forgiving but key:value is standard)
    if "ga" in list_content:
        score += 20
        feedback_parts.append("CDB list created with user 'ga'")
    else:
        feedback_parts.append("CDB list missing or does not contain user 'ga'")

    # Criteria 2: Config Registration (20 pts)
    # Check if ossec.conf references the list
    if "etc/lists/authorized_users" in ossec_conf and "<list>" in ossec_conf:
        score += 20
        feedback_parts.append("List registered in ossec.conf")
    else:
        feedback_parts.append("List NOT registered in ossec.conf")

    # Criteria 3: Rule Definition (20 pts)
    # Check local_rules.xml for ID 100500, level 12
    has_rule_id = 'id="100500"' in local_rules
    has_level_12 = 'level="12"' in local_rules
    
    if has_rule_id and has_level_12:
        score += 20
        feedback_parts.append("Rule 100500 created with level 12")
    elif has_rule_id:
        score += 10
        feedback_parts.append("Rule 100500 created but wrong level")
    else:
        feedback_parts.append("Rule 100500 NOT found")

    # Criteria 4: Functional Success (40 pts)
    # This is the most important check. Does it actually work?
    auth_ok = not functional.get("auth_triggers_100500", True) # Should NOT trigger
    unauth_ok = functional.get("unauth_triggers_100500", False) # SHOULD trigger
    
    if auth_ok and unauth_ok:
        score += 40
        feedback_parts.append("Functional Test PASSED: Whitelist is enforcing correctly")
    else:
        if not unauth_ok:
            feedback_parts.append("Functional Test FAILED: Unauthorized user 'intruder' did NOT trigger alert")
        if not auth_ok:
            feedback_parts.append("Functional Test FAILED: Authorized user 'ga' TRIGGERED alert (false positive)")
            
    # Bonus/Penalty: Check if .cdb file exists (implies compilation)
    if not result.get("list_cdb_exists", False):
        feedback_parts.append("Warning: .cdb compiled list file not found (did you restart/compile?)")
        # We don't deduct if functional test passed (maybe they compiled it elsewhere?), but usually functional fails if this is missing.

    passed = score >= 60 and (auth_ok and unauth_ok)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }