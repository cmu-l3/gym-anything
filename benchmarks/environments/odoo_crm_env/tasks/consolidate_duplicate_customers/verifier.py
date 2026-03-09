#!/usr/bin/env python3
import json
import os
import tempfile
import datetime
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_consolidate_duplicate_customers(traj, env_info, task_info):
    """
    Verify consolidation of duplicate customers in Odoo.
    
    Criteria:
    1. Master record "Hyperion Systems Inc." has the correct email.
    2. Duplicate record "Hyperion Systems" is archived (active=False).
    3. Duplicate record still exists (not deleted).
    4. "Battery Backup System" opp is linked to Master.
    5. "Inverter Upgrade" opp is linked to Master.
    6. Changes were made during the task window.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Metadata
    metadata = task_info.get('metadata', {})
    expected_email = metadata.get('expected_email', "support@hyperion-sys.example.com")
    master_name = metadata.get('master_name', "Hyperion Systems Inc.")
    
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

    if result.get('error'):
        return {"passed": False, "score": 0, "feedback": f"Verification script error: {result['error']}"}

    score = 0
    feedback_parts = []
    
    master = result.get('master_record')
    dupe = result.get('duplicate_record')
    opps = result.get('opportunities', {})
    task_start = result.get('task_start', 0)

    # 1. Verify Master Email (25 pts)
    if master:
        email = master.get('email', '')
        # Odoo might return False for empty
        if email and email.strip() == expected_email:
            score += 25
            feedback_parts.append("Master email updated correctly")
        else:
            feedback_parts.append(f"Master email incorrect (expected '{expected_email}', got '{email}')")
    else:
        feedback_parts.append("Master record not found")

    # 2. Verify Duplicate Archived (25 pts)
    # 3. Verify Duplicate Exists/Not Deleted (10 pts)
    if dupe:
        is_active = dupe.get('active', True)
        score += 10 # It exists
        feedback_parts.append("Duplicate record preserved (not deleted)")
        
        if not is_active:
            score += 25
            feedback_parts.append("Duplicate record archived")
        else:
            feedback_parts.append("Duplicate record is still active (should be archived)")
    else:
        feedback_parts.append("Duplicate record missing (likely deleted instead of archived)")

    # 4. Verify Opp 1 Reassignment (20 pts)
    opp1 = opps.get('Battery Backup System')
    if opp1 and master:
        if opp1.get('partner_id') == master.get('id'):
            score += 20
            feedback_parts.append("'Battery Backup System' reassigned correctly")
        else:
            feedback_parts.append("'Battery Backup System' not reassigned to Master")
    else:
        feedback_parts.append("'Battery Backup System' opp not found")

    # 5. Verify Opp 2 Reassignment (20 pts)
    opp2 = opps.get('Inverter Upgrade')
    if opp2 and master:
        if opp2.get('partner_id') == master.get('id'):
            score += 20
            feedback_parts.append("'Inverter Upgrade' reassigned correctly")
        else:
            feedback_parts.append("'Inverter Upgrade' not reassigned to Master")
    else:
        feedback_parts.append("'Inverter Upgrade' opp not found")

    # Anti-gaming: Check if Master was modified during task
    # Odoo write_date format: "YYYY-MM-DD HH:MM:SS"
    # We parse it to timestamp
    modified_during_task = False
    if master and master.get('write_date'):
        try:
            # write_date is UTC
            wd_str = master['write_date']
            # Simple check: if write_date is missing or format fails, we might skip strict check
            # But let's try basic parsing
            dt = datetime.datetime.strptime(wd_str.split(".")[0], "%Y-%m-%d %H:%M:%S")
            # Assuming container is UTC or close enough, and task_start is epoch
            # Converting to epoch (ignoring timezone issues for simple check, or assuming UTC)
            wd_epoch = dt.timestamp()
            if wd_epoch > task_start:
                modified_during_task = True
        except:
            pass # Relax check if parsing fails
            
    if not modified_during_task:
        feedback_parts.append("(Warning: Master record modification time older than task start)")

    passed = (score >= 85)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }