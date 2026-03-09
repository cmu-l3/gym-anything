#!/usr/bin/env python3
"""
Verifier for create_saved_pipeline_filter task.

Verifies that the agent created a persistent saved filter in Odoo CRM.
Uses database verification for the record and VLM for trajectory validation.
"""

import json
import os
import tempfile
import logging
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_create_saved_pipeline_filter(traj, env_info, task_info):
    """
    Verify the agent created the 'High Value Deals' filter correctly.
    """
    # 1. Setup - Get copy function
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System error: copy_from_env not available"}

    # 2. Retrieve result JSON from container
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve task result: {str(e)}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    # 3. Define Scoring Criteria
    score = 0
    max_score = 100
    feedback_parts = []
    
    # Metadata targets
    target_name = "High Value Deals"
    target_value = "50000"
    target_field = "expected_revenue"

    # --- CRITERION 1: Filter Record Exists (30 pts) ---
    filter_exists = result.get("filter_exists", False)
    filter_name = result.get("filter_name", "")
    
    if filter_exists and target_name.lower() in filter_name.lower():
        score += 30
        feedback_parts.append("✅ Filter record created with correct name")
    elif filter_exists:
        score += 15
        feedback_parts.append(f"⚠️ Filter created but name mismatch ('{filter_name}')")
    else:
        feedback_parts.append("❌ No filter record found")

    # --- CRITERION 2: Domain Logic Correctness (30 pts) ---
    domain = result.get("filter_domain", "")
    
    # Domain string looks like: "[('expected_revenue', '>=', 50000)]"
    has_field = target_field in domain
    has_value = target_value in domain or "50,000" in domain
    
    if has_field and has_value:
        score += 30
        feedback_parts.append("✅ Filter criteria correct (revenue >= 50k)")
    elif has_field:
        score += 15
        feedback_parts.append("⚠️ Filter targets revenue but wrong value")
    elif filter_exists:
        score += 0
        feedback_parts.append(f"❌ Filter criteria incorrect: {domain}")

    # --- CRITERION 3: Anti-Gaming Timestamp Check (15 pts) ---
    task_start = result.get("task_start", 0)
    create_time = result.get("filter_create_time", 0)
    
    if create_time > task_start:
        score += 15
        feedback_parts.append("✅ Filter created during task session")
    elif filter_exists:
        feedback_parts.append("❌ Filter pre-dated task (anti-gaming failure)")

    # --- CRITERION 4: VLM Trajectory Verification (25 pts) ---
    # We check if the agent actually used the UI to create it
    vlm_score = 0
    try:
        frames = sample_trajectory_frames(traj, n=4)
        final_img = get_final_screenshot(traj)
        
        if frames:
            prompt = """
            Analyze these screenshots of a user interacting with Odoo CRM.
            Did the user:
            1. Open the search/filter panel?
            2. Configure a custom filter for 'Expected Revenue'?
            3. Save the filter as a 'Favorite'?
            
            Reply with JSON: {"steps_observed": boolean, "confidence": float}
            """
            
            vlm_resp = query_vlm(images=frames + [final_img], prompt=prompt)
            if vlm_resp.get("success"):
                parsed = vlm_resp.get("parsed", {})
                if parsed.get("steps_observed", False):
                    vlm_score = 25
                    feedback_parts.append("✅ UI workflow verified by VLM")
                else:
                    vlm_score = 10 # Partial credit for doing something
                    feedback_parts.append("⚠️ UI workflow unclear from screenshots")
            else:
                # Fallback if VLM fails but DB is correct
                if score >= 60: vlm_score = 25 
    except Exception as e:
        logger.warning(f"VLM check failed: {e}")
        # Fallback: if DB verification is perfect, assume valid
        if score >= 75: vlm_score = 25
        
    score += vlm_score

    # 4. Final Result Calculation
    passed = score >= 70 and filter_exists and has_field and has_value
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }