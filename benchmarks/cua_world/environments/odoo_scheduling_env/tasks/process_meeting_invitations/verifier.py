#!/usr/bin/env python3
import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_process_meeting_invitations(traj, env_info, task_info):
    """
    Verify that the user accepted 'Project Alpha Sync' and declined 'Vendor Cold Call'.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # 1. Retrieve result JSON
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read task result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    # 2. Check for errors in export
    if "error" in result:
        return {"passed": False, "score": 0, "feedback": f"Export script error: {result['error']}"}

    events = result.get("events", {})
    
    # 3. Verification Logic
    # Goal: Project Alpha Sync -> accepted
    # Goal: Vendor Cold Call -> declined
    
    score = 0
    feedback = []
    
    # Check Event 1: Project Alpha Sync
    alpha_data = events.get("Project Alpha Sync")
    if not alpha_data:
        feedback.append("❌ 'Project Alpha Sync' event not found in database (deleted?).")
    else:
        status = alpha_data.get("status")
        if status == "accepted":
            score += 40
            feedback.append("✅ 'Project Alpha Sync' accepted.")
        elif status == "needsAction":
            feedback.append("❌ 'Project Alpha Sync' still pending (needs action).")
        elif status == "declined":
            feedback.append("❌ 'Project Alpha Sync' was declined (should be accepted).")
        else:
            feedback.append(f"❌ 'Project Alpha Sync' status: {status}.")

    # Check Event 2: Vendor Cold Call
    vendor_data = events.get("Vendor Cold Call")
    if not vendor_data:
        feedback.append("❌ 'Vendor Cold Call' event not found in database.")
    else:
        status = vendor_data.get("status")
        if status == "declined":
            score += 40
            feedback.append("✅ 'Vendor Cold Call' declined.")
        elif status == "needsAction":
            feedback.append("❌ 'Vendor Cold Call' still pending (needs action).")
        elif status == "accepted":
            feedback.append("❌ 'Vendor Cold Call' was accepted (should be declined).")
        else:
            feedback.append(f"❌ 'Vendor Cold Call' status: {status}.")

    # Existence Check (20 pts if both exist)
    if alpha_data and vendor_data:
        score += 20
        feedback.append("✅ Both events preserved in database.")
    else:
        feedback.append("⚠️ One or more events missing.")

    passed = score >= 100
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }