#!/usr/bin/env python3
"""
Verifier for remove_patient_identifier task.

Verification Criteria:
1. Target identifier '999-ERROR' MUST be voided in the database (50 pts).
2. The voiding action MUST have happened during the task duration (Anti-gaming) (10 pts).
3. The patient's primary identifier MUST NOT be voided (Safety) (20 pts).
4. The patient record itself MUST NOT be voided (Safety) (20 pts).
5. VLM check on trajectory to confirm UI interaction (Optional qualitative check).

Pass Threshold: 100 points (Strict: Data integrity requires perfect execution).
"""

import json
import tempfile
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_remove_patient_identifier(traj, env_info, task_info):
    """
    Verify that the agent removed the specific incorrect identifier
    without damaging the patient record.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load results from container
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
    feedback_parts = []
    
    # 1. Check Target Identifier Voided (50 pts)
    if result.get("target_identifier_voided", False):
        score += 50
        feedback_parts.append("Target identifier removed")
    else:
        feedback_parts.append("Target identifier NOT removed")
        return {"passed": False, "score": score, "feedback": "Failed: Incorrect identifier still active."}

    # 2. Anti-Gaming Timestamp Check (10 pts)
    if result.get("changes_made_during_task", False):
        score += 10
        feedback_parts.append("Action performed during task")
    else:
        feedback_parts.append("Action timestamp invalid (pre-dated task)")
        # If the ID is voided but not during task, they might have hit a stale state or manual setup error
        # We penalize heavily as this is anti-gaming
        score = 0 
        return {"passed": False, "score": score, "feedback": "Failed: Identifier was already voided before task started."}

    # 3. Safety Check: Primary ID (20 pts)
    if result.get("primary_id_safe", False):
        score += 20
        feedback_parts.append("Primary ID preserved")
    else:
        feedback_parts.append("CRITICAL: Primary ID was incorrectly removed")
        # This is a destructive failure
        return {"passed": False, "score": 0, "feedback": "Failed: You removed the patient's valid primary ID!"}

    # 4. Safety Check: Patient Record (20 pts)
    if result.get("patient_record_safe", False):
        score += 20
        feedback_parts.append("Patient record active")
    else:
        feedback_parts.append("CRITICAL: Patient record was deleted")
        return {"passed": False, "score": 0, "feedback": "Failed: You deleted the entire patient record!"}

    passed = score >= 100
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }