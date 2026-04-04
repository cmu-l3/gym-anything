#!/usr/bin/env python3
"""
Verifier for modify_lead_record task.

Verifies that:
1. The lead was found in the database.
2. Specific fields (address3, alt_phone, comments, rank, owner) match expected values.
3. The record was modified *after* the task started (anti-gaming).
4. Critical identity fields (Name) were NOT changed (collateral damage check).
"""

import json
import tempfile
import os
import logging
from datetime import datetime

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_modify_lead_record(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load Metadata
    metadata = task_info.get('metadata', {})
    expected_values = metadata.get('expected_values', {})
    
    # Defaults if metadata missing (should match task description)
    exp_addr3 = expected_values.get('address3', 'Suite 200')
    exp_alt = expected_values.get('alt_phone', '2022243121')
    exp_comm = expected_values.get('comments', 'Updated 2025 - confirmed active office. Priority contact for Q2 outreach.')
    exp_rank = str(expected_values.get('rank', '99'))
    exp_owner = expected_values.get('owner', '6666')

    # Load Result from Container
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

    # Scoring Logic
    score = 0
    feedback_parts = []
    
    # 1. Check if lead exists (Baseline)
    if not result.get('found'):
        return {
            "passed": False, 
            "score": 0, 
            "feedback": "Target lead not found in database. Did you search for the correct phone number?"
        }
    score += 10
    feedback_parts.append("Lead found")

    # 2. Check Timestamp (Anti-Gaming)
    # MySQL datetime format: YYYY-MM-DD HH:MM:SS
    modify_date_str = result.get('modify_date', '')
    task_start_ts = result.get('task_start_ts', 0)
    
    timestamp_valid = False
    if modify_date_str:
        try:
            mod_dt = datetime.strptime(modify_date_str, "%Y-%m-%d %H:%M:%S")
            mod_ts = mod_dt.timestamp()
            # Allow small clock skew, but generally mod_time should be > start_time
            if mod_ts > task_start_ts:
                timestamp_valid = True
                score += 10
                feedback_parts.append("Modification timestamp valid")
            else:
                feedback_parts.append(f"Lead not modified during task (Last mod: {modify_date_str})")
        except ValueError:
            feedback_parts.append("Could not parse modification date")
    
    if not timestamp_valid:
        # If the record wasn't modified, they didn't do the task
        return {
            "passed": False, 
            "score": score, 
            "feedback": " | ".join(feedback_parts) + " (Record was not updated during task session)"
        }

    # 3. Verify Fields
    # Address 3
    act_addr3 = result.get('address3', '')
    if act_addr3 == exp_addr3:
        score += 15
        feedback_parts.append("Address3 updated")
    else:
        feedback_parts.append(f"Address3 mismatch (Exp: '{exp_addr3}', Act: '{act_addr3}')")

    # Alt Phone
    act_alt = result.get('alt_phone', '')
    if act_alt == exp_alt:
        score += 15
        feedback_parts.append("Alt Phone updated")
    else:
        feedback_parts.append(f"Alt Phone mismatch (Exp: '{exp_alt}', Act: '{act_alt}')")

    # Comments
    act_comm = result.get('comments', '')
    if exp_comm in act_comm:
        score += 20
        feedback_parts.append("Comments updated")
    else:
        feedback_parts.append(f"Comments mismatch or incomplete")

    # Rank
    act_rank = str(result.get('rank', ''))
    if act_rank == exp_rank:
        score += 10
        feedback_parts.append("Rank updated")
    else:
        feedback_parts.append(f"Rank mismatch (Exp: {exp_rank}, Act: {act_rank})")

    # Owner
    act_owner = result.get('owner', '')
    if act_owner == exp_owner:
        score += 10
        feedback_parts.append("Owner updated")
    else:
        feedback_parts.append(f"Owner mismatch (Exp: {exp_owner}, Act: {act_owner})")

    # 4. Collateral Damage Check (Bonus/Safety)
    # Ensure Name wasn't wiped (Basic check)
    if result.get('first_name') and result.get('last_name'):
        score += 10
        feedback_parts.append("Identity fields preserved")
    else:
        feedback_parts.append("Warning: Name fields appear empty")

    # Final Evaluation
    passed = score >= 60 and timestamp_valid
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }