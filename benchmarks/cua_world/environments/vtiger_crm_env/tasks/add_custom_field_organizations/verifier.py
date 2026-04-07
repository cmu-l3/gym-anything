#!/usr/bin/env python3
"""
Verifier for add_custom_field_organizations task.

VERIFICATION STRATEGY:
1. DB Check: Did the 'Customer Tier' field get created in the Accounts module? (20 points)
2. DB Check: Is the field a picklist type (uitype 15, 16, or 33)? (10 points)
3. DB Check: Do the 4 exact picklist values exist? (5 points each = 20 points)
4. DB Check: Was it placed in the correct Layout Block? (10 points)
5. Anti-gaming: Did the total field count actually increase? (10 points)
6. VLM Trajectory: Did the agent navigate through the Layout Editor/Settings UI? (30 points)

Total points: 100
Pass Threshold: >= 70
"""

import os
import json
import tempfile
import logging
from typing import Dict, Any

from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

VLM_PROMPT = """You are verifying if a user successfully added a new custom field in Vtiger CRM.

Look at these trajectory frames capturing the user's workflow. Determine the following:
1. Did the user navigate to the CRM Settings (gear icon -> CRM Settings)?
2. Did the user use the "Module Management", "Module Layouts & Fields", or "Layout Editor" tool?
3. Can you see evidence that they interacted with the "Organizations" or "Accounts" layout?
4. Is there evidence of them adding a new field named "Customer Tier" with picklist values (Standard, Premium, Enterprise, Strategic)?

Focus on the process. Respond in JSON format:
{
    "used_settings_menu": true/false,
    "used_layout_editor": true/false,
    "interacted_with_organizations_module": true/false,
    "added_field_details": true/false,
    "confidence": "low/medium/high",
    "reasoning": "Brief explanation of the visual evidence"
}
"""

def verify_add_custom_field(traj: Dict[str, Any], env_info: Dict[str, Any], task_info: Dict[str, Any]) -> Dict[str, Any]:
    copy_from_env = env_info.get('copy_from_env')
    query_vlm = env_info.get('query_vlm')
    
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Extract metadata
    metadata = task_info.get('metadata', {})
    expected_values = metadata.get('expected_picklist_values', ["Standard", "Premium", "Enterprise", "Strategic"])
    pass_threshold = metadata.get('pass_threshold', 70)

    # 1. READ DB METRICS
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read exported JSON result: {str(e)}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    score = 0
    feedback_parts = []
    
    # Check 1: Field Existence (20 pts)
    field_exists = result.get("field_exists", False)
    if field_exists:
        score += 20
        feedback_parts.append("✅ Field 'Customer Tier' exists")
    else:
        feedback_parts.append("❌ Field 'Customer Tier' missing from Accounts module")
        return {
            "passed": False, 
            "score": score, 
            "feedback": " | ".join(feedback_parts)
        }

    # Check 2: Picklist Type (10 pts)
    # Valid picklist uitypes in Vtiger are generally 15, 16, or 33
    uitype = str(result.get("field_uitype", ""))
    if uitype in ["15", "16", "33"]:
        score += 10
        feedback_parts.append(f"✅ Field type is correct (uitype: {uitype})")
    else:
        feedback_parts.append(f"❌ Field is not a standard picklist (uitype: {uitype})")

    # Check 3: Picklist Values (20 pts max)
    actual_values_str = result.get("picklist_values", "")
    actual_values_list = [v.strip().lower() for v in actual_values_str.split(',') if v.strip()]
    
    values_found = 0
    for expected_val in expected_values:
        if expected_val.lower() in actual_values_list:
            score += 5
            values_found += 1
            
    if values_found == len(expected_values):
        feedback_parts.append("✅ All 4 picklist values present")
    else:
        feedback_parts.append(f"⚠️ Found {values_found}/{len(expected_values)} picklist values")

    # Check 4: Correct Block Layout (10 pts)
    field_block = str(result.get("field_block", ""))
    target_block = str(result.get("target_block_id", ""))
    if target_block and field_block == target_block:
        score += 10
        feedback_parts.append("✅ Field placed in 'Organization Information' block")
    elif field_block:
        score += 5
        feedback_parts.append("⚠️ Field created in different block")
    else:
        feedback_parts.append("❌ Field block not assigned properly")

    # Check 5: Count Increased (Anti-gaming) (10 pts)
    initial_count = result.get("initial_field_count", 0)
    current_count = result.get("current_field_count", 0)
    if current_count > initial_count:
        score += 10
        feedback_parts.append("✅ Field count increased")
    else:
        feedback_parts.append("❌ Field count did not increase (modified existing field?)")

    # 2. VLM TRAJECTORY VERIFICATION (30 pts)
    if query_vlm:
        frames = sample_trajectory_frames(traj, n=4)
        final_frame = get_final_screenshot(traj)
        if final_frame:
            frames.append(final_frame)
            
        if frames:
            try:
                vlm_resp = query_vlm(images=frames, prompt=VLM_PROMPT)
                if vlm_resp.get("success"):
                    vlm_parsed = vlm_resp.get("parsed", {})
                    vlm_score = 0
                    
                    if vlm_parsed.get("used_settings_menu"): vlm_score += 10
                    if vlm_parsed.get("used_layout_editor") or vlm_parsed.get("interacted_with_organizations_module"): vlm_score += 10
                    if vlm_parsed.get("added_field_details"): vlm_score += 10
                    
                    score += vlm_score
                    feedback_parts.append(f"✅ VLM Trajectory checks scored {vlm_score}/30")
                else:
                    feedback_parts.append("⚠️ VLM request failed, omitting trajectory score")
            except Exception as e:
                logger.error(f"VLM Verification error: {e}")
                feedback_parts.append("⚠️ VLM evaluation encountered an error")
        else:
            feedback_parts.append("⚠️ No trajectory frames available for VLM check")
    else:
        feedback_parts.append("⚠️ VLM service unavailable")

    # Check overall pass threshold
    passed = score >= pass_threshold
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }