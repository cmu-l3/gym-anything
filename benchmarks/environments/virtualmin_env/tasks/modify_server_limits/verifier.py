#!/usr/bin/env python3
"""
Verifier for modify_server_limits task.
"""

import json
import os
import re
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def parse_bytes(line):
    """Parse byte values from Virtualmin output strings."""
    # Example: "Server byte quota: 536870912" or "Bandwidth limit: 5368709120"
    if not line:
        return 0
    match = re.search(r'(\d+)', line)
    if match:
        return int(match.group(1))
    return 0

def parse_limit(line):
    """Parse integer limits from output strings."""
    # Example: "Maximum mailboxes: 10" or "Maximum mailboxes: Unlimited"
    if not line:
        return -1 # Missing
    if "Unlimited" in line or "unlimited" in line:
        return float('inf')
    match = re.search(r'(\d+)', line)
    if match:
        return int(match.group(1))
    return -1

def verify_modify_server_limits(traj, env_info, task_info):
    """
    Verify that server limits were correctly modified.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

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

    score = 0
    feedback_parts = []
    
    # ---------------------------------------------------------
    # 1. Disk Quota (18 points)
    # Target: 512 MB = 536,870,912 bytes
    # Tolerance: +/- 5%
    # ---------------------------------------------------------
    quota_bytes = parse_bytes(result.get('raw_quota_line', ''))
    target_quota = 536870912
    if 0.95 * target_quota <= quota_bytes <= 1.05 * target_quota:
        score += 18
        feedback_parts.append("Disk quota correct")
    else:
        feedback_parts.append(f"Disk quota incorrect (Found: {quota_bytes}, Expected: ~{target_quota})")

    # ---------------------------------------------------------
    # 2. Bandwidth Limit (18 points)
    # Target: 5 GB = 5,368,709,120 bytes
    # Tolerance: +/- 5%
    # ---------------------------------------------------------
    bw_bytes = parse_bytes(result.get('raw_bw_line', ''))
    target_bw = 5368709120
    if 0.95 * target_bw <= bw_bytes <= 1.05 * target_bw:
        score += 18
        feedback_parts.append("Bandwidth limit correct")
    else:
        # Also check if they entered 5000 MB instead of 5120 MB
        alt_target = 5000 * 1024 * 1024
        if 0.95 * alt_target <= bw_bytes <= 1.05 * alt_target:
             score += 18
             feedback_parts.append("Bandwidth limit correct (decimal GB accepted)")
        else:
            feedback_parts.append(f"Bandwidth limit incorrect (Found: {bw_bytes})")

    # ---------------------------------------------------------
    # 3. Max Mailboxes (13 points)
    # Target: 10
    # ---------------------------------------------------------
    max_mail = parse_limit(result.get('raw_max_mail_line', ''))
    if max_mail == 10:
        score += 13
        feedback_parts.append("Max mailboxes correct")
    else:
        feedback_parts.append(f"Max mailboxes incorrect (Found: {max_mail})")

    # ---------------------------------------------------------
    # 4. Max Aliases (13 points)
    # Target: 20
    # ---------------------------------------------------------
    max_alias = parse_limit(result.get('raw_max_alias_line', ''))
    if max_alias == 20:
        score += 13
        feedback_parts.append("Max aliases correct")
    else:
        feedback_parts.append(f"Max aliases incorrect (Found: {max_alias})")

    # ---------------------------------------------------------
    # 5. Max Databases (13 points)
    # Target: 2
    # ---------------------------------------------------------
    max_db = parse_limit(result.get('raw_max_db_line', ''))
    if max_db == 2:
        score += 13
        feedback_parts.append("Max databases correct")
    else:
        feedback_parts.append(f"Max databases incorrect (Found: {max_db})")

    # ---------------------------------------------------------
    # 6. Password Change (15 points + 10 points anti-gaming)
    # ---------------------------------------------------------
    auth_success = result.get('password_auth_success', False)
    hash_changed = result.get('password_hash_changed', False)
    
    if auth_success:
        score += 15 # Password Correct
        feedback_parts.append("Password updated correctly")
    elif hash_changed:
        score += 5  # Partial credit for changing it to something else
        feedback_parts.append("Password changed but matches incorrect value")
    else:
        feedback_parts.append("Password not changed")

    # Anti-gaming: State change detection (10 points)
    # If at least 4 items are correct, we assume state changed meaningfully
    correct_count = 0
    if "Disk quota correct" in str(feedback_parts): correct_count += 1
    if "Bandwidth limit correct" in str(feedback_parts): correct_count += 1
    if "Max mailboxes correct" in str(feedback_parts): correct_count += 1
    if "Max aliases correct" in str(feedback_parts): correct_count += 1
    if "Max databases correct" in str(feedback_parts): correct_count += 1
    
    if correct_count >= 1 or hash_changed:
        score += 10
        feedback_parts.append("State modification detected")
    
    # ---------------------------------------------------------
    # Final Decision
    # ---------------------------------------------------------
    passed = score >= 60 and correct_count >= 3
    
    return {
        "passed": passed,
        "score": score,
        "feedback": "; ".join(feedback_parts)
    }