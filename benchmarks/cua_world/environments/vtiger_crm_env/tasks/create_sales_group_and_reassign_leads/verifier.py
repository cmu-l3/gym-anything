#!/usr/bin/env python3
"""
Verifier for create_sales_group_and_reassign_leads task.
Checks both the database state of the CRM and uses the VLM 
to verify that the agent's trajectory actually involved GUI navigation.
"""

import json
import os
import tempfile
import logging

# Ensure VLM utilities are available for trajectory checks
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_create_sales_group_and_reassign_leads(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    query_vlm = env_info.get('query_vlm')
    
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_lead_count = metadata.get('expected_lead_count', 5)

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

    score = 0
    feedback_parts = []
    
    # 1. Group Existence (20 pts)
    group_exists = result.get('group_exists', False)
    if group_exists:
        score += 20
        feedback_parts.append("✅ Group 'Enterprise Sales Team' created")
    else:
        feedback_parts.append("❌ Group 'Enterprise Sales Team' not found")

    # 2. Admin Assignment (20 pts)
    admin_in_group = result.get('admin_in_group', False)
    if admin_in_group:
        score += 20
        feedback_parts.append("✅ Administrator assigned to group")
    else:
        feedback_parts.append("❌ Administrator not assigned to group")

    # 3. Target Leads Reassigned (30 pts)
    tech_reassigned = result.get('tech_leads_reassigned_count', 0)
    if tech_reassigned >= expected_lead_count:
        score += 30
        feedback_parts.append(f"✅ All {expected_lead_count} Technology leads reassigned")
    elif tech_reassigned > 0:
        partial_points = int(30 * (tech_reassigned / expected_lead_count))
        score += partial_points
        feedback_parts.append(f"⚠️ Only {tech_reassigned}/{expected_lead_count} Technology leads reassigned")
    else:
        feedback_parts.append("❌ No Technology leads were reassigned to the group")

    # 4. Precision Check / Collateral Damage (10 pts)
    non_tech_reassigned = result.get('non_tech_leads_reassigned_count', 0)
    if non_tech_reassigned == 0:
        score += 10
        feedback_parts.append("✅ Zero collateral damage (no non-Technology leads reassigned)")
    else:
        feedback_parts.append(f"❌ Collateral damage detected: {non_tech_reassigned} non-Technology leads incorrectly reassigned")

    # 5. VLM Trajectory Process Verification (20 pts)
    vlm_points = 0
    if query_vlm and traj:
        try:
            frames = sample_trajectory_frames(traj, n=4)
            final = get_final_screenshot(traj)
            images_to_check = frames + [final] if final else frames
            
            prompt = """
            Review these screenshots from a CRM system session.
            Did the user navigate through the CRM to accomplish BOTH of these actions:
            1. View the CRM Settings (specifically Users & Access / Groups)
            2. View the Leads module list and open a "Mass Edit" overlay/window?
            
            Respond in JSON format:
            {
                "navigated_to_settings": true/false,
                "opened_mass_edit_leads": true/false,
                "reasoning": "brief explanation"
            }
            """
            
            vlm_response = query_vlm(prompt=prompt, images=images_to_check)
            if vlm_response.get('success'):
                parsed = vlm_response.get('parsed', {})
                if parsed.get('navigated_to_settings'):
                    vlm_points += 10
                    feedback_parts.append("✅ VLM verified navigation to settings")
                if parsed.get('opened_mass_edit_leads'):
                    vlm_points += 10
                    feedback_parts.append("✅ VLM verified Mass Edit usage")
        except Exception as e:
            logger.error(f"VLM verification failed: {e}")
            feedback_parts.append("⚠️ VLM verification encountered an error")
    
    score += vlm_points

    # Final logic
    key_criteria_met = group_exists and (tech_reassigned == expected_lead_count) and (non_tech_reassigned == 0)
    passed = (score >= 80) and key_criteria_met

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }