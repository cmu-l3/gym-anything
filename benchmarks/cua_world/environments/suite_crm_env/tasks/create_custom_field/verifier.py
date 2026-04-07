#!/usr/bin/env python3
"""
Verifier for create_custom_field task.

This verifier checks that:
1. The metadata record exists for the new custom field.
2. The field is configured correctly (enum/dropdown on Contacts).
3. The underlying database table (contacts_cstm) contains the column.
4. The dropdown list was created with the correct options.
5. VLM confirms trajectory shows interaction with the Studio tool.
"""

import json
import os
import tempfile
import logging

# Import VLM utilities from gym_anything
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_create_custom_field(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load result from environment
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/create_custom_field_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result JSON: {e}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    score = 0
    feedback_parts = []
    
    # Check 1: Record exists in metadata table (Anti-gaming: It was wiped in setup, so must be newly created)
    field_found = result.get('field_found', False)
    if field_found:
        score += 25
        feedback_parts.append("Custom field metadata found.")
    else:
        return {"passed": False, "score": 0, "feedback": "Custom field metadata NOT found. Agent failed to create field."}

    # Check 2: Field attributes (type, module, default)
    f_type = result.get('type', '')
    f_module = result.get('module', '')
    
    if f_type == 'enum':
        score += 10
        feedback_parts.append("Field type is 'enum' (dropdown).")
    else:
        feedback_parts.append(f"Incorrect field type: expected 'enum', got '{f_type}'.")

    if f_module == 'Contacts':
        score += 10
        feedback_parts.append("Assigned to correct module (Contacts).")
    else:
        feedback_parts.append(f"Assigned to incorrect module: '{f_module}'.")

    # Check 3: Database column exists
    col_exists = result.get('column_exists', False)
    if col_exists:
        score += 15
        feedback_parts.append("Custom column exists in database (contacts_cstm).")
    else:
        feedback_parts.append("Custom column missing from contacts_cstm table.")

    # Check 4: Dropdown List options
    expected_keys = task_info.get('metadata', {}).get('expected_keys', ['phone', 'email', 'sms', 'mail'])
    dropdown_options = result.get('dropdown_options', {})
    
    if isinstance(dropdown_options, dict) and len(dropdown_options) > 0:
        found_keys = list(dropdown_options.keys())
        matches = [k for k in expected_keys if k in found_keys]
        
        if len(matches) == len(expected_keys):
            score += 20
            feedback_parts.append("All requested dropdown options created successfully.")
        else:
            partial_score = int(20 * (len(matches) / len(expected_keys)))
            score += partial_score
            feedback_parts.append(f"Partial dropdown options found ({len(matches)}/{len(expected_keys)}).")
    else:
        feedback_parts.append("Dropdown list options not found or empty.")

    # Check 5: VLM Trajectory Verification
    vlm_score = 0
    try:
        frames = sample_trajectory_frames(traj, n=4)
        final_img = get_final_screenshot(traj)
        images = frames + [final_img] if final_img else frames

        if images:
            prompt = """You are evaluating an AI agent's performance in SuiteCRM.
TASK: Create a custom dropdown field in the Contacts module using the administrative 'Studio' tool.

Analyze these screenshots from the agent's workflow trajectory.
Determine if the agent:
1. Navigated through the 'Studio' builder interface.
2. Interacted with the ModuleBuilder/Field creation forms.

Respond in JSON format:
{
    "studio_used": true/false,
    "field_forms_accessed": true/false,
    "confidence": "high/medium/low"
}
"""
            vlm_response = query_vlm(images=images, prompt=prompt)
            if vlm_response.get("success"):
                parsed = vlm_response.get("parsed", {})
                if parsed.get("studio_used"):
                    vlm_score += 10
                    feedback_parts.append("VLM confirmed Studio navigation.")
                if parsed.get("field_forms_accessed"):
                    vlm_score += 10
                    feedback_parts.append("VLM confirmed Field builder usage.")
            else:
                logger.warning(f"VLM verification failed: {vlm_response.get('error')}")
    except Exception as e:
        logger.error(f"VLM trajectory check error: {e}")
        feedback_parts.append("VLM trajectory evaluation skipped/failed.")

    score += vlm_score

    # Determine Pass/Fail (Requires at least metadata + column + some options)
    passed = score >= 65 and field_found and col_exists
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }