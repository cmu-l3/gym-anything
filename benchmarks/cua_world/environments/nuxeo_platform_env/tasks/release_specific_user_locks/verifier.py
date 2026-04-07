#!/usr/bin/env python3
"""
Verifier for release_specific_user_locks task.

Scoring Criteria:
1. 'Annual-Report-2023' must be UNLOCKED (40 pts)
2. 'Project-Proposal' must be UNLOCKED (40 pts)
3. 'Q3-Status-Report' must REMAIN LOCKED by Administrator (20 pts)

Total: 100 pts.
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_release_locks(traj, env_info, task_info):
    """
    Verify that specific locks were released while preserving others.
    """
    # 1. Retrieve result file from container
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System error: copy_from_env not available"}

    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve task results: {str(e)}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    # 2. Evaluate Lock States
    docs = result.get("documents", {})
    score = 0
    feedback = []
    
    # Check Doc 1: Annual Report (Target: Unlocked)
    doc1 = docs.get("Annual-Report-2023", {})
    if not doc1.get("exists"):
        feedback.append("Annual Report document missing.")
    elif not doc1.get("locked"):
        score += 40
        feedback.append("Annual Report successfully unlocked.")
    else:
        owner = doc1.get("lockOwner")
        feedback.append(f"Annual Report still locked by {owner}.")

    # Check Doc 2: Project Proposal (Target: Unlocked)
    doc2 = docs.get("Project-Proposal", {})
    if not doc2.get("exists"):
        feedback.append("Project Proposal document missing.")
    elif not doc2.get("locked"):
        score += 40
        feedback.append("Project Proposal successfully unlocked.")
    else:
        owner = doc2.get("lockOwner")
        feedback.append(f"Project Proposal still locked by {owner}.")

    # Check Doc 3: Q3 Status Report (Target: Locked by Administrator)
    doc3 = docs.get("Q3-Status-Report", {})
    if not doc3.get("exists"):
        feedback.append("Q3 Status Report document missing.")
    elif doc3.get("locked") and doc3.get("lockOwner") == "Administrator":
        score += 20
        feedback.append("Q3 Status Report lock correctly preserved.")
    elif doc3.get("locked"):
        owner = doc3.get("lockOwner")
        feedback.append(f"Q3 Status Report locked by wrong user: {owner} (Expected: Administrator).")
    else:
        feedback.append("Q3 Status Report was incorrectly unlocked.")

    # 3. Final Assessment
    passed = (score == 100)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }