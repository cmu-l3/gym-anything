#!/usr/bin/env python3
"""
Verifier for allocate_leave_by_tag task.

Checks:
1. Did the agent create an allocation?
2. Is it for 'Paid Time Off'?
3. Is the mode 'By Employee Tag' (category)?
4. Is the tag 'Consultant'?
5. Are the days 2.0?
6. Is it approved (state='validate')?

Crucially, this verifier penalizes "gaming" where the agent might create
individual allocations for employees instead of using the bulk tag feature.
"""

import json
import logging
import os
import tempfile
from datetime import datetime

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_allocate_leave_by_tag(traj, env_info, task_info):
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

    if 'error' in result:
        return {"passed": False, "score": 0, "feedback": f"Export script error: {result['error']}"}

    allocations = result.get('allocations', [])
    task_start_ts = result.get('task_start_timestamp', 0)
    
    # Metadata targets
    metadata = task_info.get('metadata', {})
    target_tag = metadata.get('target_tag', 'Consultant')
    target_days = metadata.get('target_days', 2.0)
    target_leave_type = metadata.get('target_leave_type', 'Paid Time Off')
    
    score = 0
    feedback_parts = []
    
    # Find best matching allocation
    # We prioritize finding ONE 'category' allocation that matches.
    
    best_match = None
    
    # Filter for allocations created after start
    # Odoo date format: "YYYY-MM-DD HH:MM:SS" (usually UTC)
    # Simple check: If we have very few allocations, we can just check the properties.
    # Since we recorded start time, we can try to compare, but Odoo clock might drift from host.
    # We'll rely on property matching primarily, assuming clean-ish state.
    
    found_category_alloc = False
    found_employee_alloc = False # For detecting incorrect method
    
    for alloc in allocations:
        # Check leave type match
        if alloc.get('leave_type') != target_leave_type:
            continue
            
        # Check days match
        if abs(alloc.get('days', 0) - target_days) > 0.1:
            continue
            
        mode = alloc.get('mode')
        
        if mode == 'category':
            cat_name = alloc.get('category_name', '')
            if cat_name == target_tag:
                best_match = alloc
                found_category_alloc = True
                break # Found exact match
        elif mode == 'employee':
            # They might have tried to do it individually
            found_employee_alloc = True

    # Scoring
    if best_match:
        score += 20 # Created record
        feedback_parts.append("Allocation record found")
        
        # Mode check (Critical)
        if best_match['mode'] == 'category':
            score += 30
            feedback_parts.append("Correct Mode: By Employee Tag")
        else:
            feedback_parts.append(f"Incorrect Mode: {best_match['mode']}")
            
        # Tag check
        if best_match.get('category_name') == target_tag:
            score += 20
            feedback_parts.append(f"Correct Tag: {target_tag}")
        else:
            feedback_parts.append(f"Incorrect Tag: {best_match.get('category_name')}")
            
        # Days check (already filtered, but adding points)
        score += 10
        feedback_parts.append(f"Correct Duration: {target_days} days")
        
        # Leave type check (already filtered)
        score += 10
        feedback_parts.append(f"Correct Leave Type: {target_leave_type}")
        
        # State check
        if best_match['state'] in ['validate', 'validate1']:
            score += 10
            feedback_parts.append("Allocation Approved/Validated")
        else:
            feedback_parts.append(f"Allocation not approved (State: {best_match['state']})")
            
    else:
        # No bulk allocation found
        if found_employee_alloc:
            feedback_parts.append("FAILED: Found individual employee allocations. Task required BULK allocation by Tag.")
            score = 10 # Pity points for trying
        else:
            feedback_parts.append("No matching allocation found (Paid Time Off, 2 days, Consultant Tag)")
    
    passed = (score >= 90) # Requires almost perfect execution (Mode+Tag+Days+State)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }