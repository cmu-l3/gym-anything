#!/usr/bin/env python3
"""
Verifier for Create Custom Role task.
Combines Database verification (for existence/metadata) and VLM (for UI permissions).
"""

import json
import os
import tempfile
import logging
from gym_anything.vlm import sample_trajectory_frames, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_create_custom_role(traj, env_info, task_info):
    """
    Verifies the creation of the 'L1 Support Analyst' role.
    
    Scoring:
    1. Database: Role exists (30 pts)
    2. Database: Role name is exact match (10 pts)
    3. Database: Role description contains keywords (10 pts)
    4. Database: Role is new (count increased) (10 pts)
    5. VLM: Permission configuration (Requests=ON, Problems/Changes=OFF) (40 pts)
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    score = 0
    feedback_parts = []
    
    # --- Step 1: Database Verification ---
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

    role_found = result.get("role_found", False)
    role_details = result.get("role_details", {}) or {}
    initial_count = int(result.get("initial_role_count", 0))
    current_count = int(result.get("current_role_count", 0))

    if role_found:
        score += 30
        feedback_parts.append("Role 'L1 Support Analyst' found in database.")
        
        # Check Name Exactness
        if role_details.get("name") == "L1 Support Analyst":
            score += 10
            feedback_parts.append("Role name is exact.")
        else:
            feedback_parts.append(f"Role name mismatch: {role_details.get('name')}")

        # Check Description
        desc = role_details.get("description", "").lower()
        if "restricted" in desc or "level-1" in desc or "request" in desc:
            score += 10
            feedback_parts.append("Description contains correct context.")
        else:
            feedback_parts.append("Description missing keywords.")
            
        # Anti-gaming: Check if count increased
        if current_count > initial_count:
            score += 10
            feedback_parts.append("New role record created during task.")
        else:
            feedback_parts.append("Warning: Role count did not increase (modified existing?).")
    else:
        feedback_parts.append("Role NOT found in database.")
        # Fail immediately if DB check fails
        return {
            "passed": False, 
            "score": score, 
            "feedback": " | ".join(feedback_parts)
        }

    # --- Step 2: VLM Verification for Permissions ---
    # Since DB permission schemas are complex/opaque bits, we use VLM to check the UI interactions
    # We need to see the "Permissions" section with checkboxes.
    
    frames = sample_trajectory_frames(traj, n=5)
    
    prompt = """
    Review the sequence of screenshots from ManageEngine ServiceDesk Plus.
    The user was asked to configure a role named "L1 Support Analyst".
    
    Look for the "Permissions" or "Access Control" configuration screen.
    Verify the following specific settings:
    1. Is "Requests" or "Request Management" ENABLED/CHECKED?
    2. Are "Problems" and "Changes" DISABLED/UNCHECKED?
    3. Is "Admin" or "Setup" DISABLED/UNCHECKED?
    
    Return JSON:
    {
        "permissions_screen_visible": boolean,
        "requests_enabled": boolean,
        "others_disabled": boolean,
        "role_saved": boolean,
        "confidence": "low|medium|high"
    }
    """
    
    vlm_result = query_vlm(images=frames, prompt=prompt)
    
    if vlm_result.get("success"):
        parsed = vlm_result.get("parsed", {})
        if parsed.get("permissions_screen_visible"):
            if parsed.get("requests_enabled"):
                score += 15
                feedback_parts.append("VLM: Requests permission enabled.")
            if parsed.get("others_disabled"):
                score += 15
                feedback_parts.append("VLM: Restricted permissions (Problems/Changes disabled).")
            if parsed.get("role_saved"):
                score += 10
                feedback_parts.append("VLM: Role save action observed.")
        else:
            feedback_parts.append("VLM: Could not clearly see permissions configuration screen.")
            # Fallback points if DB is perfect but VLM missed the screen (prevent false fail)
            if score >= 60: 
                score += 10
                feedback_parts.append("(Fallback point adjustment).")

    # Final Evaluation
    passed = score >= 70
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }