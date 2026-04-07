#!/usr/bin/env python3
"""
Verifier for rbac_row_level_security task.

This verifier checks both behavioral enforcement (does the user physically get 0 events 
when attempting to bypass security?) and structural configuration (is the role set up properly?)

Scoring (100 points total, PASS = 80):
1. Role 'compliance_auditor' exists (10 points)
2. User 'auditor_joe' exists and is assigned the role (20 points)
3. Index Isolation Works/Configured (20 points)
4. Row-Level Restriction Works/Configured (30 points)
5. Allowed Access Verified/Configured (20 points)
"""

import json
import tempfile
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_rbac_row_level_security(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env not available"}

    tmp = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/rbac_result.json", tmp.name)
        with open(tmp.name) as f:
            data = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}
    finally:
        if os.path.exists(tmp.name):
            os.unlink(tmp.name)

    analysis = data.get('analysis', {})
    
    admin_failed = analysis.get("admin_failed_count", -1)
    admin_accepted = analysis.get("admin_accepted_count", -1)
    auditor_failed = analysis.get("auditor_failed_count", -1)
    auditor_web = analysis.get("auditor_web_count", -1)
    auditor_accepted = analysis.get("auditor_accepted_count", -1)
    
    role_exists = analysis.get("role_exists", False)
    role_filter = analysis.get("role_srchFilter", "") or ""
    role_indexes = analysis.get("role_srchIndexesAllowed", [])
    
    # Normalize Splunk API outputs that can be strings instead of lists
    if isinstance(role_indexes, str):
        role_indexes = [role_indexes]
        
    user_exists = analysis.get("user_exists", False)
    user_roles = analysis.get("user_roles", [])
    if isinstance(user_roles, str):
        user_roles = [user_roles]

    score = 0
    feedback = []

    # Anti-gaming check: Ensure the agent didn't just delete the index to pass the 0-event checks
    if admin_failed == 0 or admin_accepted == 0:
        return {
            "passed": False, 
            "score": 0, 
            "feedback": "CRITICAL FAIL: Underlying log data was deleted/corrupted. Admin cannot see expected events.", 
            "subscores": {}
        }
    elif admin_failed == -1 or admin_accepted == -1:
        feedback.append("WARNING: Admin baseline checks timed out. Assuming data is intact.")

    # Criterion 1: Role exists
    if role_exists:
        score += 10
        feedback.append("Role 'compliance_auditor' exists")
    else:
        feedback.append("FAIL: Role 'compliance_auditor' was not created")

    # Criterion 2: User exists & assigned
    if user_exists and 'compliance_auditor' in user_roles:
        score += 20
        feedback.append("User 'auditor_joe' exists and is assigned the correct role")
    elif user_exists:
        feedback.append("FAIL: User 'auditor_joe' exists but missing 'compliance_auditor' role")
    else:
        feedback.append("FAIL: User 'auditor_joe' was not created")

    # Criterion 3: Index isolation
    if auditor_web == 0:
        score += 20
        feedback.append("Index isolation verified behaviorally (auditor sees 0 events in web_logs)")
    elif 'security_logs' in role_indexes and not any(idx in role_indexes for idx in ['web_logs', 'main', '*']):
        # Fallback to structural check if behavioral search failed (e.g. agent left "Require Password Change" checked)
        score += 15
        feedback.append("Index isolation configured structurally (behavioral query failed to execute)")
    else:
        feedback.append("FAIL: Index isolation not working or improperly configured")

    # Criterion 4: Row-Level Security
    if auditor_failed == 0 and auditor_accepted > 0:
        score += 30
        feedback.append("Row-level security verified behaviorally (auditor sees 0 'Failed' events)")
    elif "accepted" in role_filter.lower() or "success" in role_filter.lower():
        # Fallback structural check
        score += 20
        feedback.append("Row-level security configured via srchFilter (behavioral query failed to execute)")
    else:
        feedback.append("FAIL: Row-level security not working or filter missing keyword 'Accepted'")

    # Criterion 5: Allowed Access Functions
    if auditor_accepted > 0:
        score += 20
        feedback.append("Allowed access verified behaviorally (auditor can successfully query 'Accepted' events)")
    elif role_exists and ("accepted" in role_filter.lower() or "success" in role_filter.lower()) and 'security_logs' in role_indexes:
        # Fallback structural check
        score += 15
        feedback.append("Allowed access appears properly configured (behavioral query failed to execute)")
    else:
        feedback.append("FAIL: auditor_joe cannot access allowed events or configuration is broken")

    return {
        "passed": score >= 80,
        "score": score,
        "feedback": " | ".join(feedback),
        "details": {
            "admin_failed_count": admin_failed,
            "auditor_failed_count": auditor_failed,
            "auditor_accepted_count": auditor_accepted,
            "role_filter": role_filter
        }
    }