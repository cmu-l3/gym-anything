#!/usr/bin/env python3
"""
Verifier for transfer_table_order task.

Criteria:
1. An open ticket exists on Target Table (7).
2. The ticket has at least 2 items.
3. No open ticket exists on Initial Table (3).
4. VLM verifies the trajectory shows table interaction.
"""

import json
import os
import tempfile
import logging
from gym_anything.vlm import sample_trajectory_frames, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_transfer_table_order(traj, env_info, task_info):
    """
    Verifies that an order was created on Table 3 and transferred to Table 7.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System error: copy_from_env missing"}

    # Task constants
    INITIAL_TABLE = 3
    TARGET_TABLE = 7
    MIN_ITEMS = 2

    # 1. Retrieve result JSON from container
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result_data = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve task data: {str(e)}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    tickets = result_data.get('open_tickets', [])
    
    score = 0
    feedback = []
    
    # Check Database State
    target_ticket = None
    initial_table_has_ticket = False
    
    for t in tickets:
        if t['table_number'] == TARGET_TABLE:
            target_ticket = t
        elif t['table_number'] == INITIAL_TABLE:
            initial_table_has_ticket = True

    # Criterion A: Ticket exists on Table 7 (30 pts)
    if target_ticket:
        score += 30
        feedback.append(f"Success: Open ticket found on Table {TARGET_TABLE}.")
        
        # Criterion B: Item count >= 2 (20 pts)
        count = target_ticket.get('item_count', 0)
        if count >= MIN_ITEMS:
            score += 20
            feedback.append(f"Success: Ticket has {count} items (>= {MIN_ITEMS}).")
        else:
            feedback.append(f"Partial Fail: Ticket only has {count} items.")
    else:
        feedback.append(f"Fail: No open ticket found on Table {TARGET_TABLE}.")

    # Criterion C: Table 3 is empty (20 pts)
    if not initial_table_has_ticket:
        # Only award if we actually have a target ticket (avoid rewarding doing nothing)
        if target_ticket:
            score += 20
            feedback.append(f"Success: Table {INITIAL_TABLE} is correctly empty.")
    else:
        feedback.append(f"Fail: Table {INITIAL_TABLE} still has an open ticket (transfer failed or duplicate created).")

    # Criterion D: VLM Verification of Workflow (30 pts)
    # We want to see evidence that they actually interacted with the UI naturally
    frames = sample_trajectory_frames(traj, n=5)
    
    vlm_prompt = f"""
    Analyze these screenshots of a Point of Sale system interaction.
    The user task was to:
    1. Open Table {INITIAL_TABLE} and add items.
    2. Transfer the order to Table {TARGET_TABLE}.
    
    Look for:
    - A floor plan view showing tables.
    - An order entry screen with menu items.
    - Any dialogs or buttons related to "Transfer", "Edit", or "Move".
    
    Does the user appear to have performed these actions?
    """
    
    vlm_result = query_vlm(images=frames, prompt=vlm_prompt)
    
    if vlm_result and vlm_result.get('success'):
        # Simple keyword check in VLM reasoning or a structured parse if available
        # Assuming query_vlm returns a standard structure
        response_text = vlm_result.get('response', '').lower()
        if "yes" in response_text or "transfer" in response_text or "table" in response_text:
            score += 30
            feedback.append("VLM verification: Workflow looks correct.")
        else:
            score += 10 # Partial credit for just having images
            feedback.append("VLM verification: Could not clearly identify transfer workflow.")
    else:
        feedback.append("VLM verification skipped (service unavailable).")

    # Final decision
    passed = (score >= 70) and (target_ticket is not None) and (target_ticket.get('item_count', 0) >= MIN_ITEMS)

    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }