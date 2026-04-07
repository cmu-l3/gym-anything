#!/usr/bin/env python3
"""
Verifier for configure_leave_accrual_plan task.
Verifies Odoo database state using pre-exported JSON data.
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_configure_leave_accrual_plan(traj, env_info, task_info):
    """
    Verify that the accrual plan and allocation were created correctly.
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
        return {"passed": False, "score": 0, "feedback": f"Failed to load result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    max_score = 100
    feedback_parts = []
    
    # Metadata expectations
    expected_rate = 1.67
    expected_cap = 20
    
    # 1. Accrual Plan Existence (15 pts)
    if result.get("plan_found"):
        score += 15
        feedback_parts.append("Accrual plan created.")
        
        # 2. Plan Configuration (40 pts)
        levels = result.get("plan_details", {}).get("levels", [])
        if levels:
            level = levels[0]
            
            # Rate (1.67) - 15 pts
            val = level.get("added_value", 0)
            if abs(val - expected_rate) < 0.1:
                score += 15
                feedback_parts.append(f"Accrual rate correct ({val}).")
            else:
                feedback_parts.append(f"Accrual rate incorrect (expected {expected_rate}, got {val}).")
                
            # Frequency (Monthly) - 10 pts
            freq = level.get("frequency", "")
            if freq == "monthly":
                score += 10
                feedback_parts.append("Frequency correct (Monthly).")
            else:
                feedback_parts.append(f"Frequency incorrect (got {freq}).")
                
            # Cap (20 days) - 15 pts
            # cap_accrued_time is boolean, maximum_leave is float
            cap_on = level.get("cap_accrued_time")
            max_leave = level.get("maximum_leave", 0)
            
            if cap_on and abs(max_leave - expected_cap) < 1.0:
                score += 15
                feedback_parts.append("Cap configuration correct.")
            else:
                feedback_parts.append(f"Cap configuration incorrect (Enabled: {cap_on}, Max: {max_leave}).")
                
        else:
            feedback_parts.append("Plan created but no accrual levels/rules found.")
    else:
        feedback_parts.append("Accrual plan 'Monthly PTO Accrual' not found.")

    # 3. Allocation Existence (45 pts total)
    if result.get("allocation_found"):
        alloc = result.get("allocation_details", {})
        
        # Existence check passed implies 15 pts (filtered by employee in export)
        score += 15
        feedback_parts.append("Allocation created for Eli Lambert.")
        
        # Check Link to Plan (10 pts)
        plan_id = result.get("plan_details", {}).get("id")
        alloc_plan_id = alloc.get("accrual_plan_id")
        # alloc_plan_id is usually [id, name] list in Odoo read
        if isinstance(alloc_plan_id, list) and len(alloc_plan_id) > 0:
            alloc_plan_id = alloc_plan_id[0]
            
        if plan_id and alloc_plan_id == plan_id:
            score += 10
            feedback_parts.append("Allocation linked to correct plan.")
        else:
            feedback_parts.append("Allocation not linked to the created plan.")
            
        # Check Type (Paid Time Off) (10 pts)
        # Checked via leave_type_name in export
        lt_name = alloc.get("leave_type_name", "")
        if "Paid Time Off" in lt_name:
            score += 10
            feedback_parts.append("Leave type correct.")
        else:
            feedback_parts.append(f"Leave type incorrect ({lt_name}).")
            
        # Check State (Approved) (10 pts)
        state = alloc.get("state", "")
        if state in ["validate", "validate1"]:
            score += 10
            feedback_parts.append("Allocation approved.")
        else:
            feedback_parts.append(f"Allocation not approved (state: {state}).")
            
    else:
        feedback_parts.append("Accrual allocation for Eli Lambert not found.")

    passed = score >= 60
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback_parts)
    }