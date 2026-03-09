#!/usr/bin/env python3
"""
Verifier for process_retail_order task.

Criteria:
1. A new ticket must be created and settled (closed).
2. The ticket type must be 'RETAIL'.
3. The ticket must have at least 4 items (per instructions: 3 distinct, one doubled).
4. The payment method must be CASH.
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_process_retail_order(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Retrieve result file
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result JSON: {str(e)}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback = []
    
    # 1. Check if a new ticket was created (30 pts)
    if result.get('new_tickets_created', 0) > 0:
        score += 30
        feedback.append("New settled ticket created.")
    else:
        feedback.append("No new settled ticket found.")
        return {"passed": False, "score": 0, "feedback": " | ".join(feedback)}

    # 2. Check ticket type (30 pts)
    # The shell script exports is_retail_type based on the LAST closed ticket
    if result.get('is_retail_type', False):
        score += 30
        feedback.append("Correct ticket type (RETAIL).")
    else:
        actual_type = result.get('last_ticket_type', 'Unknown')
        feedback.append(f"Incorrect ticket type: {actual_type} (Expected: RETAIL).")

    # 3. Check item count (20 pts)
    # Expecting at least 4 items total (can be multiple of same item)
    item_count = result.get('item_count', 0)
    if item_count >= 4:
        score += 20
        feedback.append(f"Item count correct ({item_count} items).")
    elif item_count >= 1:
        score += 10
        feedback.append(f"Partial item count ({item_count} items, expected >= 4).")
    else:
        feedback.append("No items found on ticket.")

    # 4. Check payment method (20 pts)
    if result.get('paid_cash', False):
        score += 20
        feedback.append("Payment method correct (CASH).")
    else:
        feedback.append("Payment method incorrect or verification failed.")

    # 5. Anti-gaming check (Time)
    task_start = result.get('task_start', 0)
    task_end = result.get('task_end', 0)
    duration = task_end - task_start
    
    if duration < 10:
        feedback.append(f"WARNING: Task completed suspiciously fast ({duration}s).")
        # Penalize if score is high but time is impossible
        if score > 50:
            score = 0
            feedback.append("Score reset due to impossible completion time.")

    passed = (score >= 80) # Requires almost perfect execution (Retail + New Ticket + Cash)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback),
        "details": result
    }