#!/usr/bin/env python3
"""
Verifier for restrict_qcp_to_vendor task.
Verifies that the "Cabinet Inspection" QCP was modified to restrict it to "Gemini Furniture".
"""

import json
import tempfile
import os
import logging
from datetime import datetime

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_restrict_qcp_to_vendor(traj, env_info, task_info):
    """
    Verify the QCP modification.
    
    Criteria:
    1. QCP "Cabinet Inspection" must exist (20 pts)
    2. QCP partner_id must be set to "Gemini Furniture" (50 pts)
    3. QCP must have been modified during the task (write_date check) (10 pts)
    4. Product and Operation must still be correct (10 pts each)
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
        return {"passed": False, "score": 0, "feedback": f"Failed to load result file: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)
            
    score = 0
    feedback_parts = []
    
    # Check 1: QCP Exists
    if not result.get("qcp_exists"):
        return {
            "passed": False, 
            "score": 0, 
            "feedback": "The Quality Control Point 'Cabinet Inspection' was not found."
        }
    
    score += 20
    feedback_parts.append("QCP found")
    
    qcp = result.get("qcp_data", {})
    target_partner_id = result.get("target_partner_id")
    
    # Check 2: Partner ID (Vendor)
    # partner_id in Odoo read is typically [id, "Name"] or False
    actual_partner = qcp.get("partner_id")
    
    partner_correct = False
    if actual_partner and isinstance(actual_partner, list) and len(actual_partner) > 0:
        actual_id = actual_partner[0]
        actual_name = actual_partner[1]
        
        if actual_id == target_partner_id:
            partner_correct = True
            score += 50
            feedback_parts.append(f"Vendor correctly set to '{actual_name}'")
        else:
            feedback_parts.append(f"Vendor set to wrong partner: '{actual_name}'")
    else:
        feedback_parts.append("Vendor field is empty or invalid")
        
    # Check 3: Modification Time (Anti-gaming)
    task_start = result.get("task_start_time", 0)
    write_date_str = qcp.get("write_date", "")
    modified_recently = False
    
    if write_date_str:
        try:
            # Odoo dates are typically UTC strings like "2023-10-25 10:00:00"
            # We need to parse broadly
            # Simple check: timestamp of write_date > task_start
            # Convert string to timestamp
            # Format usually: "%Y-%m-%d %H:%M:%S"
            wd = datetime.strptime(write_date_str.split(".")[0], "%Y-%m-%d %H:%M:%S")
            wd_ts = wd.timestamp()
            
            if wd_ts >= task_start:
                modified_recently = True
                score += 10
                feedback_parts.append("Record modified during task")
            else:
                feedback_parts.append("Record not modified during task session")
        except Exception as e:
            feedback_parts.append(f"Could not verify modification time: {e}")
    else:
        feedback_parts.append("No write_date found")

    # Check 4: Product Preserved (Sanity check)
    # product_ids is many2many in quality.point
    product_ids = qcp.get("product_ids", [])
    if product_ids:
        score += 10
        feedback_parts.append("Product preserved")
    else:
        feedback_parts.append("Warning: Product link removed")

    # Check 5: Operation Preserved
    picking_type_ids = qcp.get("picking_type_ids", [])
    if picking_type_ids:
        score += 10
        feedback_parts.append("Operation preserved")
    else:
        feedback_parts.append("Warning: Operation link removed")
        
    passed = (score >= 80) and partner_correct and modified_recently
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }