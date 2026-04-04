#!/usr/bin/env python3
"""
Verifier for verify_friend_deletion_safeguard task.

Task: Add 'Safeguard Pilot', attempt to delete, cancel confirmation, verify persistence.

Verification Strategy:
1. Programmatic: Check if "Safeguard Pilot" exists in the final UI dump (Persistence).
2. VLM: Analyze trajectory to verify:
   - Friend was added.
   - Deletion was attempted (dialog appeared).
   - Cancel was clicked.
"""

import json
import os
import tempfile
import logging
from gym_anything.vlm import sample_trajectory_frames, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_friend_deletion_safeguard(traj, env_info, task_info):
    """
    Verify the agent added a friend, triggered the delete dialog, and cancelled it.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # ================================================================
    # 1. Programmatic Verification (Persistence)
    # ================================================================
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/sdcard/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve task result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    friend_persists = result.get("friend_found", False)

    # ================================================================
    # 2. VLM Trajectory Verification (Process)
    # ================================================================
    # We need to see the intermediate steps: Add -> Delete Attempt -> Cancel
    frames = sample_trajectory_frames(traj, n=8)  # Sample more frames to catch the dialog
    
    prompt = """
    You are verifying an Android app task. The user must:
    1. Add a friend named "Safeguard Pilot".
    2. Attempt to delete this friend (via long-press, swipe, or menu) to show a CONFIRMATION DIALOG.
    3. Tap 'Cancel' or 'No' in the dialog (NOT 'Yes' or 'Delete').
    4. Ensure the friend remains in the list.

    Review the screenshots and answer:
    - Was "Safeguard Pilot" added to the list?
    - Did a "Remove Friend", "Delete", or "Are you sure?" confirmation dialog appear?
    - Did the user tap "Cancel", "No", or click outside to dismiss it (refusing the deletion)?
    - Is "Safeguard Pilot" visible in the final state?

    Output JSON:
    {
        "friend_added": true/false,
        "delete_dialog_appeared": true/false,
        "cancellation_action": true/false,
        "final_visibility": true/false,
        "reasoning": "..."
    }
    """

    vlm_result = query_vlm(images=frames, prompt=prompt)
    vlm_data = vlm_result.get("parsed", {})
    
    # Extract VLM signals
    vlm_added = vlm_data.get("friend_added", False)
    vlm_dialog = vlm_data.get("delete_dialog_appeared", False)
    vlm_cancel = vlm_data.get("cancellation_action", False)
    vlm_visible = vlm_data.get("final_visibility", False)

    # ================================================================
    # Scoring Logic
    # ================================================================
    score = 0
    feedback = []

    # Criterion 1: Friend Added (20 pts)
    if vlm_added or friend_persists:
        score += 20
        feedback.append("Friend 'Safeguard Pilot' added")
    else:
        feedback.append("Failed to add friend")

    # Criterion 2: Deletion Attempted / Dialog Seen (30 pts)
    if vlm_dialog:
        score += 30
        feedback.append("Deletion confirmation dialog triggered")
    else:
        feedback.append("No deletion confirmation dialog seen (did you try to remove the friend?)")

    # Criterion 3: Cancellation (20 pts)
    if vlm_cancel:
        score += 20
        feedback.append("Deletion cancelled correctly")
    elif vlm_dialog and friend_persists:
        # If we saw the dialog and the friend is still there, we infer cancel was clicked
        score += 20
        feedback.append("Deletion cancelled (inferred)")
    else:
        feedback.append("Did not clearly cancel deletion")

    # Criterion 4: Persistence (30 pts)
    # We prioritize the programmatic check (friend_persists) as it's exact
    if friend_persists:
        score += 30
        feedback.append("Friend persisted in list")
    elif vlm_visible:
        # Fallback to visual check if dump failed
        score += 30
        feedback.append("Friend visible in list (visual check)")
    else:
        feedback.append("Friend NOT found in final list (was it deleted?)")

    # Pass Threshold: 80 points
    # Requires: Add + Dialog + Persistence (20+30+30=80) or Add + Dialog + Cancel + Persistence (100)
    passed = score >= 80

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback),
        "details": {
            "vlm_analysis": vlm_data,
            "programmatic_found": friend_persists
        }
    }