#!/usr/bin/env python3
"""
Verifier for configure_message_auditing task.
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_configure_message_auditing(traj, env_info, task_info):
    """
    Verify Rocket.Chat message auditing settings.
    
    Expected State:
    1. Message_Read_Receipt_Enabled == True
    2. Message_AllowEditing == True
    3. Message_AllowEditing_BlockEditInMinutes == 5
    4. Message_AllowDeleting == False
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}
        
    # Copy result file
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result: {e}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)
            
    if result.get("api_access_failed"):
        return {"passed": False, "score": 0, "feedback": "Verification failed: API inaccessible"}

    settings = result.get("final_settings", {})
    
    score = 0
    feedback = []
    
    # 1. Read Receipts (25 points)
    # API returns JSON boolean (true/false) which Python loads as True/False
    val_receipts = settings.get("Message_Read_Receipt_Enabled")
    if val_receipts is True:
        score += 25
        feedback.append("Read Receipts enabled (PASS)")
    else:
        feedback.append(f"Read Receipts expected True, got {val_receipts}")

    # 2. Allow Editing (10 points)
    val_editing = settings.get("Message_AllowEditing")
    if val_editing is True:
        score += 10
        feedback.append("Editing Allowed (PASS)")
    else:
        feedback.append(f"Editing expected True, got {val_editing}")

    # 3. Block Edit Time (30 points)
    # API likely returns integer
    val_block = settings.get("Message_AllowEditing_BlockEditInMinutes")
    if val_block == 5:
        score += 30
        feedback.append("Block Editing set to 5 mins (PASS)")
    else:
        feedback.append(f"Block Editing expected 5, got {val_block}")

    # 4. Allow Deleting (35 points)
    val_deleting = settings.get("Message_AllowDeleting")
    if val_deleting is False:
        score += 35
        feedback.append("Deleting Disabled (PASS)")
    else:
        feedback.append(f"Deleting expected False, got {val_deleting}")

    passed = (score == 100)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }