#!/usr/bin/env python3
"""Verifier for refactor_push_down_method task."""

import json
import tempfile
import os
import logging
import re

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_refactor_push_down_method(traj, env_info, task_info):
    """
    Verify the 'Push Down' refactoring task.
    
    Criteria:
    1. Transport.java (Superclass): Must NOT contain 'checkTirePressure' or 'MAX_TIRE_PSI' (20 pts)
    2. Truck.java (Target Subclass): Must contain 'checkTirePressure' and 'MAX_TIRE_PSI' (30 pts)
    3. Ship.java/Drone.java (Sibling Subclasses): Must NOT contain 'checkTirePressure' (10 pts)
    4. Project compiles successfully (40 pts)
    """
    
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}
        
    # Load result
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result: {e}"}
    finally:
        os.unlink(temp_result.name)

    score = 0
    feedback_parts = []
    
    # Extract contents
    transport_content = result.get('transport_content', '')
    truck_content = result.get('truck_content', '')
    ship_content = result.get('ship_content', '')
    compile_success = result.get('compile_success', False)

    # Helper patterns
    method_pattern = r'checkTirePressure\s*\('
    field_pattern = r'MAX_TIRE_PSI'
    
    # CRITERION 1: Removed from Superclass (20 pts)
    in_transport_method = bool(re.search(method_pattern, transport_content))
    in_transport_field = bool(re.search(field_pattern, transport_content))
    
    if not in_transport_method and not in_transport_field:
        score += 20
        feedback_parts.append("Correctly removed from Transport.java")
    else:
        feedback_parts.append(f"Transport.java still has members (Method: {in_transport_method}, Field: {in_transport_field})")

    # CRITERION 2: Added to Target Subclass (30 pts)
    in_truck_method = bool(re.search(method_pattern, truck_content))
    in_truck_field = bool(re.search(field_pattern, truck_content))
    
    if in_truck_method and in_truck_field:
        score += 30
        feedback_parts.append("Correctly added to Truck.java")
    elif in_truck_method:
        score += 15
        feedback_parts.append("Method added to Truck, but field missing")
    else:
        feedback_parts.append("Members not found in Truck.java")

    # CRITERION 3: Not in Sibling Subclasses (10 pts)
    in_ship = bool(re.search(method_pattern, ship_content))
    
    if not in_ship:
        score += 10
        feedback_parts.append("Ship.java correctly clean")
    else:
        feedback_parts.append("Error: Ship.java contains the method")

    # CRITERION 4: Compilation (40 pts)
    if compile_success:
        score += 40
        feedback_parts.append("Project compiles successfully")
    else:
        feedback_parts.append("Build failed (check Maven output)")

    # VLM Verification (Optional Bonus/Confirmation)
    # We use this to confirm UI usage if programmatic checks are borderline, 
    # but for code refactoring, the file state is the ultimate truth.
    # We'll rely primarily on code state for scoring.
    
    passed = score >= 90
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }