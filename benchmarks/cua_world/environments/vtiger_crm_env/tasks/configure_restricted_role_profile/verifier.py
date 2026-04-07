#!/usr/bin/env python3
"""
Verifier for configure_restricted_role_profile task.

Verifies:
1. Profile "Restricted Sales" exists.
2. Leads and Contacts delete permissions are disabled (1 = disabled in Vtiger DB).
3. Role "Junior Sales Rep" exists.
4. Role parent hierarchy ends with the Sales Manager role ID directly above the new role.
5. Role is linked to the "Restricted Sales" profile.
6. VLM trajectory verification to ensure UI usage.
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

VLM_PROMPT = """You are evaluating an agent configuring user roles and profiles in Vtiger CRM.
Look at the sequence of screenshots. Did the agent navigate through the "CRM Settings" area (specifically "Profiles" and "Roles") and interact with the interface to create these records?

Return a JSON with the following structure:
{
    "interacted_with_settings": true/false,
    "reasoning": "Brief explanation of what the agent did in the screenshots."
}
"""

def verify_role_profile(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    query_vlm = env_info.get('query_vlm')
    
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available."}

    # Fetch result JSON
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load task result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback_parts = []
    
    # 1. Check Profile Exists (15 pts)
    profile_exists = result.get("profile_exists", False)
    profile_id = result.get("profile_id", "")
    if profile_exists:
        score += 15
        feedback_parts.append("Profile 'Restricted Sales' created")
    else:
        feedback_parts.append("Profile 'Restricted Sales' NOT found")

    # 2. Check Role Exists (15 pts)
    role_exists = result.get("role_exists", False)
    role_id = result.get("role_id", "")
    if role_exists:
        score += 15
        feedback_parts.append("Role 'Junior Sales Rep' created")
    else:
        feedback_parts.append("Role 'Junior Sales Rep' NOT found")

    # 3. Check Permissions (In Vtiger, 0 = Allow, 1 = Deny) (20 pts)
    leads_delete = result.get("leads_delete_permission", "")
    contacts_delete = result.get("contacts_delete_permission", "")
    
    if leads_delete == "1" and contacts_delete == "1":
        score += 20
        feedback_parts.append("Delete permissions correctly revoked for Leads and Contacts")
    elif leads_delete == "1" or contacts_delete == "1":
        score += 10
        feedback_parts.append("Delete permissions partially revoked (missed one module)")
    elif profile_exists:
        feedback_parts.append(f"Delete permissions incorrect. Expected 1 (deny), got Leads:{leads_delete}, Contacts:{contacts_delete}")

    # 4. Check Role Hierarchy (15 pts)
    # The parentrole field looks like H1::H2::H_SalesMgr::H_JuniorRep
    hierarchy = result.get("role_parent_hierarchy", "")
    sales_mgr_id = result.get("sales_mgr_role_id", "NOT_FOUND")
    
    if hierarchy and sales_mgr_id in hierarchy:
        # Check if it directly reports to Sales Manager
        parts = hierarchy.split('::')
        if len(parts) >= 2 and parts[-2] == sales_mgr_id and parts[-1] == role_id:
            score += 15
            feedback_parts.append("Role correctly placed under Sales Manager")
        else:
            score += 5
            feedback_parts.append("Role in hierarchy, but parent might not be exactly Sales Manager")
    elif role_exists:
        feedback_parts.append("Role hierarchy incorrect")

    # 5. Check Role Linked to Profile (15 pts)
    assigned_profile = result.get("role_assigned_profile", "")
    if profile_exists and role_exists and assigned_profile == profile_id:
        score += 15
        feedback_parts.append("Role successfully linked to new Profile")
    elif role_exists:
        feedback_parts.append("Role NOT linked to correct Profile")

    # 6. VLM Trajectory check (20 pts)
    vlm_passed = False
    if query_vlm:
        from gym_anything.vlm import sample_trajectory_frames
        frames = sample_trajectory_frames(traj, n=5)
        if frames:
            try:
                vlm_resp = query_vlm(images=frames, prompt=VLM_PROMPT)
                if vlm_resp and vlm_resp.get("success"):
                    parsed = vlm_resp.get("parsed", {})
                    if parsed.get("interacted_with_settings", False):
                        score += 20
                        vlm_passed = True
                        feedback_parts.append("VLM confirmed UI interaction")
                    else:
                        feedback_parts.append("VLM didn't detect proper UI interaction")
            except Exception as e:
                logger.error(f"VLM error: {e}")
                feedback_parts.append("VLM verification skipped/failed")
    else:
        # Give points automatically if VLM missing but DB checks pass
        if profile_exists and role_exists:
            score += 20
            feedback_parts.append("VLM missing, awarded points based on DB records")

    # Final Evaluation
    key_criteria_met = profile_exists and role_exists and leads_delete == "1" and contacts_delete == "1" and assigned_profile == profile_id
    passed = score >= 80 and key_criteria_met

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }