#!/usr/bin/env python3
"""
Verifier for optimize_autoreply_behavior task.

Verifies that the agent configured the auto-reply settings correctly:
1. Global auto-reply is ENABLED
2. Auto-reply to NEW conversations is ENABLED
3. Auto-reply to REPLIES is DISABLED (This is the critical fix)
"""

import json
import tempfile
import os
import logging
from datetime import datetime

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def parse_db_bool(value):
    """Parse database boolean/tinyint value (0/1 or '0'/'1')."""
    if value is None:
        return False
    str_val = str(value).strip()
    return str_val == '1' or str_val.lower() == 'true'

def verify_optimize_autoreply_behavior(traj, env_info, task_info):
    """
    Verify the mailbox auto-reply configuration.
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
    
    # Check if mailbox was found
    if not result.get('mailbox_found', False):
        return {
            "passed": False,
            "score": 0,
            "feedback": "Target mailbox 'Facilities' not found in database"
        }

    # Extract current state
    is_enabled = parse_db_bool(result.get('is_auto_reply'))
    is_new = parse_db_bool(result.get('is_auto_reply_new'))
    is_reply = parse_db_bool(result.get('is_auto_reply_reply'))
    
    # 1. Verify Global Auto-Reply is ENABLED (20 pts)
    if is_enabled:
        score += 20
        feedback_parts.append("Global auto-reply enabled")
    else:
        feedback_parts.append("Global auto-reply disabled (should be enabled)")

    # 2. Verify Auto-Reply to New Conversations is ENABLED (30 pts)
    if is_new:
        score += 30
        feedback_parts.append("Send to new conversations enabled")
    else:
        feedback_parts.append("Send to new conversations disabled (should be enabled)")

    # 3. Verify Auto-Reply to Replies is DISABLED (40 pts) - CRITICAL
    if not is_reply:
        score += 40
        feedback_parts.append("Send to replies disabled (Correct)")
    else:
        feedback_parts.append("Send to replies is still ENABLED (Incorrect - causes loops)")

    # 4. Anti-Gaming / Change Detection (10 pts)
    # Check if state actually changed from initial
    initial_raw = result.get('initial_db_state', '').strip()
    # Initial state was 1, 1, 1 (all enabled)
    # If current state is different, we award points
    
    current_sig = f"{int(is_enabled)}\t{int(is_new)}\t{int(is_reply)}"
    if current_sig != initial_raw:
        score += 10
        feedback_parts.append("Configuration was modified")
    else:
        feedback_parts.append("Configuration unchanged from default")

    # Pass threshold: Must have all settings correct (Strict)
    # 20 + 30 + 40 + 10 = 100
    passed = (score == 100)

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }