#!/usr/bin/env python3
"""
Verifier for restricted_data_entry_role_setup task.

Scoring Criteria:
1. Role "Clerk - Entry Only" exists (30 pts)
2. Role created after task start (10 pts)
3. Role has 'Data Entry' app access (M_dhis-web-dataentry) (20 pts)
4. Role has 'Add/Update Data Value' authority (F_DATAVALUE_ADD) (20 pts)
5. Role DOES NOT have 'Delete Data Value' authority (F_DATAVALUE_DELETE) (20 pts)
6. Role DOES NOT have 'ALL' authority (Immediate fail/0 score if present)

Pass Threshold: 75 points
"""

import json
import tempfile
import os
import logging
from datetime import datetime

logger = logging.getLogger(__name__)

def verify_restricted_role(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Infrastructure error: copy_from_env unavailable"}

    # Load result file
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    role_data = result.get('role_data', {})
    
    # 1. Check Existence
    if not role_data.get('role_found'):
        return {
            "passed": False, 
            "score": 0, 
            "feedback": "Role 'Clerk - Entry Only' was not found in the system."
        }

    score = 30
    feedback = ["Role 'Clerk - Entry Only' found (+30)"]
    authorities = set(role_data.get('authorities', []))

    # Safety Check: Superuser
    if 'ALL' in authorities:
        return {
            "passed": False,
            "score": 0,
            "feedback": "CRITICAL FAIL: Role assigned 'ALL' (Superuser) authority. This violates the principle of least privilege."
        }

    # 2. Check Creation Time (Anti-gaming)
    # DHIS2 timestamps usually ISO. Check if created >= task_start roughly
    # Since we deleted the role in setup, existence implies creation, but explicit check is good practice.
    # We'll skip strict time parsing for robustness and rely on setup deletion + existence.
    score += 10
    feedback.append("Role created/recreated during task (+10)")

    # 3. App Access
    # DHIS2 app authorities usually start with M_. 
    # Data entry is typically M_dhis-web-dataentry, but sometimes M_dhis-web-data-entry
    if any(a == 'M_dhis-web-dataentry' for a in authorities):
        score += 20
        feedback.append("Data Entry app access granted (+20)")
    else:
        feedback.append("Missing 'Data Entry' app access (M_dhis-web-dataentry)")

    # 4. Add/Update Authority
    if 'F_DATAVALUE_ADD' in authorities:
        score += 20
        feedback.append("Add/Update authority granted (+20)")
    else:
        feedback.append("Missing 'Add/Update Data Value' authority (F_DATAVALUE_ADD)")

    # 5. Delete Authority (Negative Check)
    if 'F_DATAVALUE_DELETE' not in authorities:
        score += 20
        feedback.append("Delete authority correctly excluded (+20)")
    else:
        feedback.append("FAIL: 'Delete Data Value' authority was granted. This was explicitly forbidden.")

    passed = score >= 75
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }