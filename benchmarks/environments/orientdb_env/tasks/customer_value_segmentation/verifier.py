#!/usr/bin/env python3
"""
Verifier for Customer Value Segmentation Task.
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_customer_value_segmentation(traj, env_info, task_info):
    """
    Verifies the task based on:
    1. Database Schema: 'CustomerTier' exists on Profiles.
    2. Database Data: Tracer accounts have correct tiers (Platinum/Gold/Silver).
    3. Output File: JSON file contains the Platinum users.
    """
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
        return {"passed": False, "score": 0, "feedback": f"Failed to load result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback = []
    
    db_state = result.get("db_state", {})
    agent_output = result.get("agent_output", {})

    # 1. Verify Schema (20 pts)
    if db_state.get("property_exists"):
        score += 20
        feedback.append("Schema: CustomerTier property added.")
        if db_state.get("property_type") != "STRING":
            feedback.append(f"(Warning: Type is {db_state.get('property_type')}, expected STRING)")
    else:
        feedback.append("Schema: CustomerTier property MISSING.")

    # 2. Verify Data Segmentation (60 pts total)
    tracers = db_state.get("tracers", {})
    
    # VIP Tracer -> Platinum (20 pts)
    vip_tier = tracers.get("vip_tracer@example.com")
    if vip_tier == "Platinum":
        score += 20
        feedback.append("Data: VIP user correctly segmented as Platinum.")
    else:
        feedback.append(f"Data: VIP user incorrect. Expected 'Platinum', got '{vip_tier}'.")

    # Mid Tracer -> Gold (20 pts)
    mid_tier = tracers.get("mid_tracer@example.com")
    if mid_tier == "Gold":
        score += 20
        feedback.append("Data: Mid-tier user correctly segmented as Gold.")
    else:
        feedback.append(f"Data: Mid-tier user incorrect. Expected 'Gold', got '{mid_tier}'.")

    # Low/Inactive Tracer -> Silver (20 pts)
    low_tier = tracers.get("low_tracer@example.com")
    zero_tier = tracers.get("inactive_tracer@example.com")
    
    if low_tier == "Silver" and zero_tier == "Silver":
        score += 20
        feedback.append("Data: Low/Zero spenders correctly segmented as Silver.")
    elif low_tier == "Silver" or zero_tier == "Silver":
        score += 10
        feedback.append("Data: Partial success on Silver segmentation.")
    else:
        feedback.append(f"Data: Low spenders incorrect. Got {low_tier}, {zero_tier}.")

    # 3. Verify Output File (20 pts)
    if agent_output.get("exists") and agent_output.get("valid_json"):
        content = agent_output.get("content", [])
        if isinstance(content, list):
            # Check if vip_tracer is in the list
            found_vip = any(u.get("Email") == "vip_tracer@example.com" for u in content)
            # Check if low_tracer is NOT in the list
            found_low = any(u.get("Email") == "low_tracer@example.com" for u in content)
            
            if found_vip and not found_low:
                score += 20
                feedback.append("Export: JSON file correctly lists Platinum users.")
            elif found_vip:
                score += 10
                feedback.append("Export: JSON file contains Platinum users but may include others.")
            else:
                score += 5
                feedback.append("Export: JSON file exists but missing expected VIP user.")
        else:
            feedback.append("Export: JSON format invalid (expected list).")
    else:
        feedback.append("Export: Output file missing or invalid.")

    return {
        "passed": score >= 80,
        "score": score,
        "feedback": " ".join(feedback)
    }