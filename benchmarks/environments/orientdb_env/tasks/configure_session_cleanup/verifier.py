#!/usr/bin/env python3
"""
Verifier for configure_session_cleanup task.

Criteria:
1. Schema: 'UserSessions' class exists with 'Token', 'Created', 'UserEmail'.
2. Function: 'cleanup_sessions' exists and code contains delete logic.
3. Schedule: 'OSchedule' entry exists for the function.
4. Data Logic:
   - Zero expired records remain (Created < 24h ago).
   - Some active records remain (Created > 24h ago) -> Proof of selective delete.
   - Total records approx 5 (since we started with 10 and deleted 5).
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_session_cleanup(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Copy result JSON
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

    score = 0
    feedback = []

    # 1. Schema Check (20 pts)
    if result.get("class_exists"):
        props = result.get("properties", [])
        required = ["Token", "Created", "UserEmail"]
        missing = [p for p in required if p not in props]
        if not missing:
            score += 20
            feedback.append("Schema UserSessions created correctly.")
        else:
            score += 10
            feedback.append(f"UserSessions class exists but missing properties: {missing}")
    else:
        feedback.append("UserSessions class NOT found.")

    # 2. Function Check (25 pts)
    if result.get("function_exists"):
        code = result.get("function_code", "").lower()
        if "delete" in code and "usersessions" in code:
            score += 25
            feedback.append("Function cleanup_sessions exists with DELETE logic.")
        else:
            score += 15
            feedback.append("Function cleanup_sessions exists but code may be incorrect (no DELETE found).")
    else:
        feedback.append("Function cleanup_sessions NOT found.")

    # 3. Schedule Check (25 pts)
    if result.get("schedule_exists"):
        score += 25
        feedback.append("Scheduler configured for the function.")
    else:
        feedback.append("No OSchedule entry found for cleanup_sessions.")

    # 4. Data Policy Enforcement (30 pts)
    total = result.get("total_records", 0)
    expired = result.get("expired_records_remaining", 0)
    active = result.get("active_records_remaining", 0)
    
    # Critical Check: Did they actually delete the old stuff?
    if result.get("class_exists"):
        if expired == 0:
            # Good, but did they delete everything?
            if active > 0:
                score += 30
                feedback.append(f"Policy enforced correctly: {active} active sessions remain, 0 expired.")
            elif total == 0:
                # Deleted everything
                score += 10
                feedback.append("Policy enforced too aggressively: All records deleted (including active ones).")
            else:
                # Should not happen if expired=0 and active=0 implies total=0
                pass
        else:
            # Expired records still exist
            feedback.append(f"Policy FAILED: {expired} expired sessions still exist in database.")
    
    # Check data realism (bonus/sanity check)
    if "@" in result.get("sample_email", ""):
        feedback.append("Data contains valid-looking emails.")

    passed = score >= 65 and result.get("function_exists") and result.get("schedule_exists")

    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback),
        "details": result
    }