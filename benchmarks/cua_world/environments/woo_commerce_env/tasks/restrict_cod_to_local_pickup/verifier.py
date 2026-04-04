#!/usr/bin/env python3
"""
Verifier for restrict_cod_to_local_pickup task.

Criteria:
1. COD Payment Gateway must be ENABLED (20 pts)
2. COD Title must be "Pay on Pickup" (20 pts)
3. COD must be restricted to SPECIFIC shipping methods (40 pts)
4. Restriction must INCLUDE 'Local Pickup' and EXCLUDE 'Flat Rate' (20 pts)
   - If 'Any method' is selected (empty list), score for restriction is 0.

Anti-gaming:
- Checks performed against database state.
- IDs generated dynamically in setup are verified against final config.
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_restrict_cod_to_local_pickup(traj, env_info, task_info):
    """
    Verify the agent configured COD settings correctly.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Copy result JSON from container
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    # Extract data
    cod_settings = result.get("cod_settings", {})
    target_id = result.get("target_method_id", "")
    distractor_id = result.get("distractor_method_id", "")
    
    score = 0
    feedback_parts = []
    
    # 1. Check Enabled (20 pts)
    is_enabled = cod_settings.get("enabled", "no") == "yes"
    if is_enabled:
        score += 20
        feedback_parts.append("COD enabled")
    else:
        feedback_parts.append("COD disabled")

    # 2. Check Title (20 pts)
    title = cod_settings.get("title", "").strip()
    expected_title = "Pay on Pickup"
    if title.lower() == expected_title.lower():
        score += 20
        feedback_parts.append(f"Title correct ('{title}')")
    elif expected_title.lower() in title.lower():
        score += 10
        feedback_parts.append(f"Title partial match ('{title}')")
    else:
        feedback_parts.append(f"Title incorrect ('{title}')")

    # 3. Check Restrictions (60 pts total)
    # enable_for_methods can be an empty string (meaning 'all') or a list
    enable_for_methods = cod_settings.get("enable_for_methods", "")
    
    # Normalize to list
    if isinstance(enable_for_methods, str):
        if enable_for_methods == "":
            methods_list = [] # Represents "All methods" in this context (no restriction)
        else:
            methods_list = [enable_for_methods]
    elif isinstance(enable_for_methods, list):
        methods_list = enable_for_methods
    else:
        methods_list = []

    # Check if ANY restriction is applied
    # In WooCommerce, if the list is empty, it means "Available for ALL shipping methods"
    # The goal is to restrict it, so list must NOT be empty
    if not methods_list:
        feedback_parts.append("No shipping method restrictions applied (available for all)")
    else:
        score += 40 # Points for applying *some* restriction
        feedback_parts.append("Restrictions applied")
        
        # Check specific IDs
        has_target = target_id in methods_list
        has_distractor = distractor_id in methods_list
        
        if has_target and not has_distractor:
            score += 20
            feedback_parts.append("Correctly restricted to Local Pickup only")
        elif has_target and has_distractor:
            feedback_parts.append("Incorrect: Allowed for both Local Pickup and Flat Rate")
        elif not has_target:
            feedback_parts.append("Incorrect: Local Pickup NOT allowed")

    return {
        "passed": score >= 80,
        "score": score,
        "feedback": " | ".join(feedback_parts),
        "details": {
            "enabled": is_enabled,
            "title": title,
            "methods_list": methods_list,
            "target_id": target_id
        }
    }