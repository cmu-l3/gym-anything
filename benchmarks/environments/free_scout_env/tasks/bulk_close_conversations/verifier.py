#!/usr/bin/env python3
"""
Verifier for bulk_close_conversations task.
Checks if specific conversations were closed while others remained open.
"""

import json
import tempfile
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_bulk_close_conversations(traj, env_info, task_info):
    """
    Verify that the 3 target conversations are closed and the 2 keep-open ones are active.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load result
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

    score = 0
    feedback_parts = []
    
    conversations = result.get('conversations', {})
    task_start = result.get('task_start_time', 0)
    
    # 1. Verify Target Conversations (Should be Closed, Status=3)
    # 12 points each = 36 points total
    targets = ['target_1', 'target_2', 'target_3']
    closed_count = 0
    
    for key in targets:
        conv = conversations.get(key)
        if not conv:
            feedback_parts.append(f"{key} data missing")
            continue
            
        status = str(conv.get('status', ''))
        updated_at = int(conv.get('updated_at', 0))
        
        if status == '3':
            # Check if it was updated during task (Anti-gaming)
            if updated_at >= task_start:
                score += 12
                closed_count += 1
                feedback_parts.append(f"Target {key} closed correctly")
            else:
                score += 6 # Half points if closed but timestamp dubious (unlikely given setup)
                closed_count += 1
                feedback_parts.append(f"Target {key} closed (timestamp warning)")
        else:
            feedback_parts.append(f"Target {key} NOT closed (status={status})")

    # 2. Verify Keep-Open Conversations (Should be Active, Status=1)
    # 17 points each = 34 points total
    # ANTI-GAMING: Only award these points if at least ONE target was closed.
    # Otherwise "do nothing" gets 34 points.
    keeps = ['keep_1', 'keep_2']
    kept_open_count = 0
    
    if closed_count > 0:
        for key in keeps:
            conv = conversations.get(key)
            if not conv:
                feedback_parts.append(f"{key} data missing")
                continue
                
            status = str(conv.get('status', ''))
            
            if status == '1':
                score += 17
                kept_open_count += 1
                feedback_parts.append(f"Non-target {key} kept open correctly")
            else:
                feedback_parts.append(f"Non-target {key} was INCORRECTLY closed (status={status})")
    else:
        feedback_parts.append("No target conversations were closed - 0 points for keeping others open (anti-gaming)")

    # 3. Verify Mailbox Counts (Global check)
    # 30 points total
    counts = result.get('mailbox_counts', {})
    
    # We expect at least 3 closed (our targets)
    if int(counts.get('closed', 0)) >= 3:
        score += 15
        feedback_parts.append("Total closed count correct (>=3)")
    else:
        feedback_parts.append(f"Total closed count low ({counts.get('closed', 0)})")

    # We expect at least 2 active (our keep-opens)
    if int(counts.get('active', 0)) >= 2:
        score += 15
        feedback_parts.append("Total active count correct (>=2)")
    else:
        feedback_parts.append(f"Total active count low ({counts.get('active', 0)})")

    # Calculate final result
    pass_threshold = 60
    passed = score >= pass_threshold
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts),
        "details": {
            "closed_correctly": closed_count,
            "kept_open": kept_open_count,
            "total_score": score
        }
    }