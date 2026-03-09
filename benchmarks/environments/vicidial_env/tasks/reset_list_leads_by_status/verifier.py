#!/usr/bin/env python3
"""
Verifier for reset_list_leads_by_status task.

Verifies that:
1. Leads with statuses B, N, A were reset (called_since_last_reset='N').
2. Leads with statuses SALE, DNC were NOT reset (called_since_last_reset='Y').
3. Changes happened during the task window.
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def parse_mysql_output(raw_str):
    """Parses 'STATUS\tCOUNT|STATUS\tCOUNT' string into a dict."""
    if not raw_str:
        return {}
    result = {}
    # Split lines by pipe if multiple lines, or just process if single
    lines = raw_str.split('|')
    for line in lines:
        parts = line.split('\t')
        if len(parts) >= 2:
            status = parts[0].strip()
            try:
                count = int(parts[1].strip())
                result[status] = count
            except ValueError:
                continue
    return result

def verify_reset_list_leads(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load metadata
    metadata = task_info.get('metadata', {})
    target_statuses = set(metadata.get('target_statuses', ['B', 'N', 'A']))
    protected_statuses = set(metadata.get('protected_statuses', ['SALE', 'DNC']))
    
    # Expected counts (from setup script: 10 of each target, 5 of each protected)
    expected_target_count = 10
    expected_protected_count = 5

    # Copy result
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result file: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    # Parse DB results
    # reset_counts: Leads that are now 'N' (Ready to dial)
    reset_counts = parse_mysql_output(result.get('reset_counts_raw', ''))
    
    # protected_counts_remaining: Leads that are still 'Y' (Called/Done)
    protected_counts_remaining = parse_mysql_output(result.get('protected_counts_raw', ''))
    
    modified_count = result.get('modified_leads_count', 0)

    score = 0
    feedback = []
    
    # CRITERION 1: Target Statuses Reset (60 points)
    # Check if B, N, A are in reset_counts with correct numbers
    targets_passed = True
    for status in target_statuses:
        count = reset_counts.get(status, 0)
        if count == expected_target_count:
            score += 20
            feedback.append(f"Status {status} correctly reset ({count}/{expected_target_count})")
        else:
            targets_passed = False
            feedback.append(f"Status {status} NOT reset correctly (found {count}, expected {expected_target_count})")
    
    # CRITERION 2: Protected Statuses SAFE (40 points)
    # Check if SALE, DNC are still 'Y' (i.e., appear in protected_counts_remaining)
    # If they were reset, they would appear in reset_counts (bad) or not appear in protected_counts (bad)
    protected_passed = True
    for status in protected_statuses:
        # We expect them to be in the "Still Y" list
        count = protected_counts_remaining.get(status, 0)
        
        # Also check if they accidentally ended up in the "Reset N" list
        reset_bad_count = reset_counts.get(status, 0)
        
        if count == expected_protected_count and reset_bad_count == 0:
            score += 20
            feedback.append(f"Status {status} correctly PRESERVED ({count}/{expected_protected_count})")
        else:
            protected_passed = False
            feedback.append(f"Status {status} COMPROMISED! (Reset: {reset_bad_count}, Preserved: {count})")

    # Anti-gaming check
    if modified_count == 0:
        feedback.append("WARNING: No database records were modified during the task window.")
        score = 0
        targets_passed = False

    passed = targets_passed and protected_passed and (modified_count > 0)

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }