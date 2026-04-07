#!/usr/bin/env python3
"""
Verifier for customize_contacts_travel_layout task.
Evaluates CRM module layout structural modifications and uses VLM for trajectory verification.
"""

import json
import os
import tempfile
import logging
from typing import Dict, Any

from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_customize_layout(traj, env_info, task_info) -> Dict[str, Any]:
    copy_from_env = env_info.get('copy_from_env')
    query_vlm = env_info.get('query_vlm')
    
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load Result JSON
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

    schema_data = result.get('schema_data', {})
    if not schema_data or 'error' in schema_data:
        return {"passed": False, "score": 0, "feedback": f"Database error: {schema_data.get('error', 'Unknown')}"}

    # Meta requirements
    initial_max_block_id = schema_data.get('initial_max_block_id', 0)
    initial_max_field_id = schema_data.get('initial_max_field_id', 0)
    
    block = schema_data.get('block')
    fields = schema_data.get('fields', [])
    picklist_values = schema_data.get('picklist_values', {})
    
    score = 0
    feedback = []
    
    # 1. Verify Block Creation (15 points)
    block_valid = False
    if block:
        try:
            block_id = int(block.get('blockid', 0))
            if block_id > initial_max_block_id:
                score += 15
                block_valid = True
                feedback.append("✅ New 'Travel Preferences' block successfully created.")
            else:
                feedback.append("❌ 'Travel Preferences' block exists but wasn't newly created (Anti-Gaming Triggered).")
        except ValueError:
            pass
    else:
        feedback.append("❌ 'Travel Preferences' block not found.")
        
    # 2. Verify Fields (10 points each)
    expected_fields = {
        "Passport Expiry": {"types": [5], "found": False},
        "Frequent Flyer Number": {"types": [1, 2], "found": False},
        "Preferred Seating": {"types": [15, 16, 33], "found": False},
        "Dietary Restrictions": {"types": [15, 16, 33], "found": False}
    }
    
    fields_valid_count = 0
    for f in fields:
        label = f.get('fieldlabel', '').strip()
        f_id = int(f.get('fieldid', 0))
        u_type = int(f.get('uitype', 0))
        
        # Ensure field is newly created
        if f_id <= initial_max_field_id:
            continue
            
        for exp_lbl, exp_data in expected_fields.items():
            if exp_lbl.lower() in label.lower() and not exp_data["found"]:
                if u_type in exp_data["types"]:
                    score += 10
                    fields_valid_count += 1
                    exp_data["found"] = True
                    feedback.append(f"✅ Found correct field: '{label}'.")
                else:
                    feedback.append(f"⚠️ Found '{label}' but incorrect UI type ({u_type}).")

    for exp_lbl, exp_data in expected_fields.items():
        if not exp_data["found"]:
            feedback.append(f"❌ Missing or invalid field: '{exp_lbl}'.")

    # 3. Verify Picklist Values (10 points each)
    expected_seating = ["Window", "Aisle", "No Preference"]
    expected_dietary = ["None", "Vegetarian", "Vegan", "Halal", "Kosher", "Gluten-Free"]
    
    # Check Seating
    seating_vals = None
    for k, v in picklist_values.items():
        if "Seating" in k: seating_vals = v
        
    if seating_vals is not None:
        if all(val in seating_vals for val in expected_seating):
            score += 10
            feedback.append("✅ Preferred Seating picklist values are correct.")
        else:
            feedback.append(f"❌ Preferred Seating values mismatch: {seating_vals}")
            
    # Check Dietary
    dietary_vals = None
    for k, v in picklist_values.items():
        if "Dietary" in k: dietary_vals = v
        
    if dietary_vals is not None:
        if all(val in dietary_vals for val in expected_dietary):
            score += 10
            feedback.append("✅ Dietary Restrictions picklist values are correct.")
        else:
            feedback.append(f"❌ Dietary Restrictions values mismatch: {dietary_vals}")

    # 4. VLM Verification (25 points) - Checking visual trajectory for workflow
    vlm_score = 0
    if query_vlm:
        frames = sample_trajectory_frames(traj, n=4)
        final_frame = get_final_screenshot(traj)
        if final_frame:
            frames.append(final_frame)
            
        prompt = """You are evaluating a CRM administrator's actions.
Look at these sequence of screenshots from an agent automating Vtiger CRM.
Did the agent navigate to the CRM Settings (specifically the "Module Layouts & Fields" or "Module Management" area) and edit a module's layout or add custom fields?
Respond with JSON:
{
    "navigated_to_settings": true/false,
    "edited_layout_or_fields": true/false,
    "confidence": "high/medium/low",
    "reasoning": "Brief explanation"
}"""
        
        try:
            vlm_response = query_vlm(prompt=prompt, images=frames)
            if vlm_response.get("success"):
                parsed = vlm_response.get("parsed", {})
                if parsed.get("navigated_to_settings") and parsed.get("edited_layout_or_fields"):
                    vlm_score = 25
                    feedback.append("✅ VLM confirmed visual trajectory of layout configuration.")
                else:
                    vlm_score = 10 if parsed.get("navigated_to_settings") else 0
                    feedback.append(f"⚠️ VLM trajectory evaluation partial/failed: {parsed.get('reasoning')}")
            else:
                feedback.append("⚠️ VLM query failed.")
        except Exception as e:
            feedback.append(f"⚠️ VLM error: {str(e)}")
            
    score += vlm_score
    
    # Final pass/fail determination
    # Require block creation, at least 2 fields created properly, and >70 score
    key_criteria_met = block_valid and fields_valid_count >= 2
    passed = (score >= 70) and key_criteria_met

    return {
        "passed": passed,
        "score": score,
        "feedback": "\n".join(feedback),
        "details": {
            "block_valid": block_valid,
            "fields_found": fields_valid_count,
            "programmatic_score": score - vlm_score,
            "vlm_score": vlm_score
        }
    }