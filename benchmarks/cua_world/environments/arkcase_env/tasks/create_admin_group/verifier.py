#!/usr/bin/env python3
"""
Verifier for create_admin_group task in ArkCase.

Verification Strategy:
1. Programmatic: Check if group exists in LDAP (via samba-tool output).
2. Programmatic: Check if group is visible in ArkCase API.
3. Programmatic: Check if group description matches expectation.
4. VLM: Verify UI trajectory shows Admin module usage.
"""

import json
import os
import tempfile
import logging
from gym_anything.vlm import sample_trajectory_frames, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_create_admin_group(traj, env_info, task_info):
    """
    Verify that the 'FOIA_Senior_Analysts' group was created.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load result from container
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load task results: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    metadata = task_info.get('metadata', {})
    expected_name = metadata.get('expected_group_name', 'FOIA_Senior_Analysts')
    expected_desc = metadata.get('expected_description', 'Senior FOIA analysts')

    score = 0
    feedback_parts = []
    
    # --- Criterion 1: LDAP Existence (30 pts) ---
    ldap_exists = result.get('ldap_exists', False)
    if ldap_exists:
        score += 30
        feedback_parts.append("✅ Group created in LDAP directory")
    else:
        feedback_parts.append("❌ Group NOT found in LDAP directory")

    # --- Criterion 2: API Visibility (20 pts) ---
    api_exists = result.get('api_exists', False)
    if api_exists:
        score += 20
        feedback_parts.append("✅ Group visible via ArkCase API")
    else:
        feedback_parts.append("❌ Group NOT visible in ArkCase API")

    # --- Criterion 3: Metadata/Description Check (15 pts) ---
    ldap_details = result.get('ldap_details', '')
    desc_found = False
    # Check if expected description text appears in the LDAP details dump
    # (Samba might store it in 'description' or similar field)
    if expected_desc.lower() in ldap_details.lower():
        desc_found = True
        score += 15
        feedback_parts.append("✅ Group description matches expectations")
    elif ldap_exists:
        feedback_parts.append("⚠️ Group exists but description mismatch or not found")
    
    # --- Criterion 4: Anti-Gaming / Freshness (10 pts) ---
    count_diff = result.get('count_diff', 0)
    if count_diff > 0:
        score += 10
        feedback_parts.append("✅ New group count increased")
    elif ldap_exists:
        feedback_parts.append("⚠️ Group exists but count didn't increase (maybe modified existing?)")

    # --- Criterion 5: VLM Trajectory Verification (25 pts) ---
    # We want to confirm the agent actually used the Admin UI
    vlm_score = 0
    
    # Only run VLM if we have at least partial programmatic success or if we want to debug failure
    query_func = env_info.get('query_vlm')
    if query_func:
        frames = sample_trajectory_frames(traj, n=4)
        
        prompt = """
        You are verifying an ArkCase task. The user is supposed to:
        1. Login to ArkCase
        2. Navigate to the 'Admin' or 'Administration' module.
        3. Go to Group Management.
        4. Fill out a form to create a group named 'FOIA_Senior_Analysts'.

        Look at the image sequence. 
        - Do you see the ArkCase Admin interface (often has a dark sidebar or different layout than the dashboard)?
        - Do you see a form for creating a user or group?
        - Do you see the text 'FOIA_Senior_Analysts' being typed?

        Answer in JSON:
        {
            "admin_interface_visible": boolean,
            "group_form_visible": boolean,
            "typing_group_name": boolean,
            "confidence": float
        }
        """
        
        try:
            vlm_resp = query_func(images=frames, prompt=prompt)
            if vlm_resp.get('success'):
                parsed = vlm_resp.get('parsed', {})
                if parsed.get('admin_interface_visible'): vlm_score += 10
                if parsed.get('group_form_visible'): vlm_score += 10
                if parsed.get('typing_group_name'): vlm_score += 5
                
                if vlm_score > 0:
                    feedback_parts.append(f"✅ VLM verified UI workflow ({vlm_score}/25)")
                else:
                    feedback_parts.append("❌ VLM did not observe Admin UI usage")
            else:
                feedback_parts.append("⚠️ VLM analysis failed")
                # Fallback: if LDAP exists, we give partial benefit of doubt for UI
                if ldap_exists: vlm_score = 15 
        except Exception as e:
            logger.warning(f"VLM error: {e}")
            if ldap_exists: vlm_score = 15

    score += vlm_score

    # Final Pass Logic
    # Must have created group in LDAP/API (Primary criteria) AND score >= 60
    passed = (ldap_exists or api_exists) and score >= 60

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }