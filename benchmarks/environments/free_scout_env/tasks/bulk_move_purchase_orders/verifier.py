#!/usr/bin/env python3
"""
Verifier for bulk_move_purchase_orders task.

Scoring Criteria:
1. Target tickets moved to Sales mailbox: 15 points each (5 * 15 = 75 pts)
2. Distractor tickets remain in Support mailbox: 15 points (all or nothing)
3. Action Verified (timestamp updated): 10 points

Pass Threshold: 75 points
"""

import json
import os
import tempfile
import logging
from datetime import datetime

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_bulk_move(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Copy result file
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

    # Extract Data
    sales_id = result.get("sales_mailbox_id", "")
    support_id = result.get("support_mailbox_id", "")
    start_time_ts = int(result.get("start_time", 0))
    
    targets = result.get("targets", [])
    distractors = result.get("distractors", [])
    
    score = 0
    feedback_parts = []
    
    if not sales_id or not support_id:
        return {"passed": False, "score": 0, "feedback": "Critical: Mailbox IDs not found"}

    # 1. Verify Targets (75 pts max)
    # Expected subjects defined in task metadata
    target_subjects = task_info.get("metadata", {}).get("target_subjects", [])
    
    # Map found targets by subject partial match
    moved_count = 0
    action_verified = False
    
    for subject_key in target_subjects:
        # Find corresponding entry in results
        match = next((t for t in targets if subject_key in t["subject"]), None)
        
        if match:
            # Check Mailbox
            if str(match["mailbox_id"]) == str(sales_id):
                score += 15
                moved_count += 1
                
                # Check Timestamp (Anti-gaming)
                try:
                    updated_at_str = match["updated_at"]
                    # Format is typically "YYYY-MM-DD HH:MM:SS"
                    updated_dt = datetime.strptime(updated_at_str, "%Y-%m-%d %H:%M:%S")
                    updated_ts = updated_dt.timestamp()
                    
                    if updated_ts > start_time_ts:
                        action_verified = True
                except Exception:
                    pass # Date parsing fail shouldn't fail the whole task if mailbox is right
            else:
                feedback_parts.append(f"Failed to move '{subject_key}' (still in MB {match['mailbox_id']})")
        else:
            feedback_parts.append(f"Target '{subject_key}' not found in DB")

    if moved_count == len(target_subjects):
        feedback_parts.append(f"All {moved_count} targets moved successfully")
    elif moved_count > 0:
        feedback_parts.append(f"Moved {moved_count}/{len(target_subjects)} targets")

    # 2. Verify Distractors (15 pts)
    distractors_ok = True
    for d in distractors:
        if str(d["mailbox_id"]) != str(support_id):
            distractors_ok = False
            feedback_parts.append(f"Distractor '{d['subject']}' was incorrectly moved!")
    
    if distractors_ok and len(distractors) > 0:
        score += 15
        feedback_parts.append("Distractors correctly preserved")
    elif not distractors_ok:
        feedback_parts.append("Penalty: Distractors were moved")

    # 3. Action Verified (10 pts)
    if action_verified:
        score += 10
        feedback_parts.append("Timestamps confirm active modification")
    else:
        feedback_parts.append("Warning: No timestamp updates detected (possible pre-configuration)")

    passed = (score >= 75)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }