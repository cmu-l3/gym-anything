#!/usr/bin/env python3
"""
Verifier for create_readonly_dns_auditor task.

SCORING CRITERIA:
1. User 'dns_auditor' exists (30 pts)
2. User has access to 'bind8' module (20 pts)
3. BIND permissions set to Read-Only (readonly=1) (30 pts)
4. BIND permissions restrict Config and Stop (noconfig=1, stop=0) (20 pts)
"""

import json
import os
import tempfile
import logging
import sys

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_create_readonly_dns_auditor(traj, env_info, task_info):
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
    
    # Criterion 1: User Exists
    if result.get('user_exists', False):
        score += 30
        feedback_parts.append("User 'dns_auditor' created")
    else:
        return {
            "passed": False, 
            "score": 0, 
            "feedback": "User 'dns_auditor' was not found in Webmin users."
        }

    # Criterion 2: Module Access
    if result.get('has_bind_access', False):
        score += 20
        feedback_parts.append("Access to BIND module granted")
    else:
        feedback_parts.append("User missing access to BIND module")

    # Criterion 3: Read-Only Mode
    # Ideally readonly=1. Sometimes verifying complex ACLs is tricky, 
    # but Webmin usually sets this explicit flag for the "Read-only" radio button.
    acl_readonly = result.get('acl_readonly', '0')
    if str(acl_readonly) == '1':
        score += 30
        feedback_parts.append("Read-only mode active")
    else:
        feedback_parts.append("Read-only mode NOT set (user can likely edit zones)")

    # Criterion 4: Strict Security (No Config, No Stop)
    security_score = 0
    acl_noconfig = result.get('acl_noconfig', '0')
    acl_stop = result.get('acl_stop', '1') # 1 means can stop

    if str(acl_noconfig) == '1':
        security_score += 10
        feedback_parts.append("Module config locked")
    else:
        feedback_parts.append("Module config accessible")

    if str(acl_stop) == '0':
        security_score += 10
        feedback_parts.append("Stop server disabled")
    else:
        feedback_parts.append("Stop server allowed")
    
    score += security_score

    # Final Check
    passed = (score >= 80) # Must have User + BIND Access + ReadOnly (30+20+30=80)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }