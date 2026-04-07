#!/usr/bin/env python3
"""
Verifier for create_attribute_set task in iDempiere.
Verifies that the agent created a Product Attribute Set with the correct tracking configuration.
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_create_attribute_set(traj, env_info, task_info):
    """
    Verify the Product Attribute Set creation.
    
    Criteria:
    1. Record exists with correct Search Key (15 pts)
    2. Name matches 'Serialized Lot Tracking' (10 pts)
    3. Serial Number tracking is enabled (20 pts)
    4. Lot tracking is enabled (20 pts)
    5. Guarantee Days is 365 (15 pts)
    6. Instance Attribute is enabled (10 pts)
    7. Anti-gaming: Record created after task start (10 pts)
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Copy result JSON from container
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
    max_score = 100
    feedback_parts = []
    
    # 1. Record Existence (15 pts)
    if not result.get('record_found', False):
        return {
            "passed": False, 
            "score": 0, 
            "feedback": "No Attribute Set found with Search Key 'SER_LOT_TRACK'. Did you save the record?",
            "details": result
        }
    
    score += 15
    feedback_parts.append("Record created")
    
    # 2. Name Check (10 pts)
    expected_name = "Serialized Lot Tracking"
    actual_name = result.get('name', '')
    if actual_name.lower().strip() == expected_name.lower().strip():
        score += 10
        feedback_parts.append("Name correct")
    else:
        feedback_parts.append(f"Name mismatch (expected '{expected_name}', got '{actual_name}')")
        
    # 3. Serial Number Tracking (20 pts)
    if result.get('is_ser_no') == 'Y':
        score += 20
        feedback_parts.append("Serial tracking enabled")
    else:
        feedback_parts.append("Serial tracking NOT enabled")
        
    # 4. Lot Tracking (20 pts)
    if result.get('is_lot') == 'Y':
        score += 20
        feedback_parts.append("Lot tracking enabled")
    else:
        feedback_parts.append("Lot tracking NOT enabled")
        
    # 5. Guarantee Days (15 pts)
    days = result.get('guarantee_days', 0)
    if days == 365:
        score += 15
        feedback_parts.append("Guarantee days correct")
    else:
        feedback_parts.append(f"Guarantee days incorrect (expected 365, got {days})")
        
    # 6. Instance Attribute (10 pts)
    if result.get('is_instance_attribute') == 'Y':
        score += 10
        feedback_parts.append("Instance attribute enabled")
    else:
        feedback_parts.append("Instance attribute NOT enabled")
        
    # 7. Anti-gaming Timestamp Check (10 pts)
    created_epoch = result.get('created_epoch', 0)
    task_start = result.get('task_start_epoch', 0)
    
    if created_epoch > task_start:
        score += 10
        feedback_parts.append("Timestamp valid")
    else:
        # If created before start, it might be an old record or the check failed
        if created_epoch == 0:
            feedback_parts.append("Timestamp check failed (creation time unknown)")
        else:
            feedback_parts.append("Record existed before task started")
            # Severe penalty for using pre-existing data if setup script didn't clean it
            score = max(0, score - 50)

    # Final Pass Determination
    # Must have the record, correct tracking flags (Serial+Lot), and timestamp validity
    passed = (
        result.get('record_found') and
        result.get('is_ser_no') == 'Y' and
        result.get('is_lot') == 'Y' and
        score >= 60
    )
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }