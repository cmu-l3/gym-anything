#!/usr/bin/env python3
import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_triage_complaint_case(traj, env_info, task_info):
    """
    Verifies that the complaint case was successfully triaged (status changed).
    
    Scoring Logic:
    1. Case Found & API Accessible (20 pts)
    2. Status Changed from Initial 'NEW' (40 pts)
    3. Status is a Valid Active State (e.g. ACTIVE, IN_PROGRESS) (40 pts)
    """
    
    # 1. Setup & Data Retrieval
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System Error: copy_from_env not available"}

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

    # 2. Extract Data
    case_found = result.get("case_found", False)
    initial_status = result.get("initial_status", "NEW").upper()
    final_status = result.get("final_status", "UNKNOWN").upper()
    app_running = result.get("app_running", False)

    # Metadata for valid states
    metadata = task_info.get("metadata", {})
    # Default valid active states if not specified
    valid_active_states = metadata.get("target_statuses", ["ACTIVE", "IN_PROGRESS", "TRIAGED", "OPEN"])
    forbidden_states = metadata.get("forbidden_statuses", ["NEW", "CREATED", "CLOSED", "REJECTED"])

    score = 0
    feedback = []

    # 3. Evaluate Criteria

    # Criterion 1: Infrastructure Check (20 pts)
    if case_found:
        score += 20
        feedback.append("Case successfully identified in system.")
    else:
        feedback.append("Failed to locate the target case in the system via API.")
        return {"passed": False, "score": 0, "feedback": " ".join(feedback)}

    # Criterion 2: Status Change (40 pts)
    if final_status != initial_status:
        score += 40
        feedback.append(f"Case status successfully changed from {initial_status} to {final_status}.")
    else:
        feedback.append(f"Case status remained unchanged ({initial_status}). Agent did not trigger workflow.")

    # Criterion 3: Valid Target State (40 pts)
    # We want to ensure it went forward (Active), not just closed or cancelled immediately
    if final_status in valid_active_states:
        score += 40
        feedback.append(f"Case is in valid active state: {final_status}.")
    elif final_status in forbidden_states:
        # If they just closed it without working on it, or it stayed NEW
        if final_status == "CLOSED":
            feedback.append("Case was CLOSED immediately instead of triaged/activated.")
        elif final_status == initial_status:
            pass # Already handled above
        else:
            feedback.append(f"Status '{final_status}' is not a valid active state.")
    else:
        # Fallback for unknown states that might be valid but not in our explicit list
        # If it changed and isn't closed/rejected, we give partial credit or benefit of doubt
        # checking if it looks "active"
        if "ACTIV" in final_status or "PROGRESS" in final_status:
            score += 40
            feedback.append(f"Case is in state {final_status}, accepted as active.")
        else:
            # Partial credit for moving it somewhere at least
            score += 10
            feedback.append(f"Case moved to unexpected state: {final_status}.")

    # 4. Final Verification
    passed = (score >= 80)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback),
        "details": {
            "initial": initial_status,
            "final": final_status,
            "case_id": result.get("case_id")
        }
    }