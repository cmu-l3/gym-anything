#!/usr/bin/env python3
"""
Verifier for set_conversation_pending task.

Verifies that:
1. The specific conversation's status is now 2 (Pending).
2. The conversation was updated AFTER the task started.
3. No other conversations were incorrectly set to Pending.
4. Visual confirmation via VLM (UI shows "Pending").
"""

import json
import tempfile
import os
import logging
import sys

# Add parent directory for shared utilities if needed
# sys.path.insert(0, str(Path(__file__).parent.parent))
# from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_set_conversation_pending(traj, env_info, task_info):
    """
    Verify the agent set the conversation status to Pending.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Import VLM utils inside function to avoid import errors if not available
    try:
        from gym_anything.vlm import get_final_screenshot, query_vlm
    except ImportError:
        logger.warning("VLM utils not available, skipping visual check")
        get_final_screenshot = None
        query_vlm = None

    # Load result from container
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

    # Extract data
    current_status = int(result.get('current_status', 0))
    initial_status = int(result.get('initial_status', 1))
    updated_at = int(result.get('updated_at_ts', 0))
    task_start = int(result.get('task_start_ts', 0))
    other_pending = int(result.get('other_pending_count', 0))
    
    score = 0
    feedback_parts = []
    
    # --- Criterion 1: Status is Pending (50 pts) ---
    # FreeScout Statuses: 1=Active, 2=Pending, 3=Closed, 4=Spam
    if current_status == 2:
        score += 50
        feedback_parts.append("Status correctly set to Pending (2)")
    elif current_status == 1:
        feedback_parts.append("Status is still Active (1)")
    elif current_status == 3:
        feedback_parts.append("Status was set to Closed (3) instead of Pending")
    else:
        feedback_parts.append(f"Status is incorrect ({current_status})")

    # --- Criterion 2: Status actually changed (15 pts) ---
    if current_status != initial_status:
        score += 15
        feedback_parts.append("Status changed from initial state")
    else:
        feedback_parts.append("Status unchanged")

    # --- Criterion 3: Updated during task (15 pts) ---
    # Allow a small buffer for clock skew, though docker usually shares host clock
    if updated_at >= task_start:
        score += 15
        feedback_parts.append("Conversation updated during task window")
    else:
        feedback_parts.append(f"Conversation not updated during task (Last update: {updated_at}, Start: {task_start})")

    # --- Criterion 4: Precision / Anti-gaming (10 pts) ---
    if other_pending == 0:
        score += 10
        feedback_parts.append("No other conversations affected")
    else:
        feedback_parts.append(f"Penalty: {other_pending} wrong conversation(s) set to Pending")
        # No points for this section

    # --- Criterion 5: VLM Visual Verification (10 pts) ---
    vlm_score = 0
    if get_final_screenshot and query_vlm:
        try:
            final_img = get_final_screenshot(traj)
            prompt = """
            Look at this screenshot of a help desk interface (FreeScout).
            I am looking for a specific conversation: "Conference Room B Display".
            
            1. Is the conversation visible?
            2. Does it show a 'Pending' status indicator? (Look for:
               - An orange/yellow icon or label
               - The word "Pending" in a status column or dropdown
               - A yellow background highlight often used for pending items)
            
            Return JSON: {"visible": bool, "status_is_pending": bool}
            """
            vlm_response = query_vlm(images=[final_img], prompt=prompt)
            # Simple parsing assuming the VLM returns a dict-like structure or we parse it
            # For robustness, we'll assume the VLM wrapper handles JSON parsing or we do basic string check
            if isinstance(vlm_response, dict):
                is_pending = vlm_response.get("status_is_pending", False)
            else:
                is_pending = "true" in str(vlm_response).lower() and "pending" in str(vlm_response).lower()

            if is_pending:
                vlm_score = 10
                feedback_parts.append("Visual verification passed (Pending status visible)")
            else:
                feedback_parts.append("Visual verification failed (Pending status not clear)")
        except Exception as e:
            logger.warning(f"VLM check failed: {e}")
            feedback_parts.append("Visual verification skipped due to error")
    
    score += vlm_score

    # Final Pass Logic
    # Must have correct status AND been updated recently
    passed = (current_status == 2) and (updated_at >= task_start) and (score >= 65)

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }