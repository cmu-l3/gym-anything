#!/usr/bin/env python3
"""
Verifier for configure_ldap_auth task.

Verifies that the user configured the LDAP settings in Artifactory correctly.
Uses the exported JSON result from the container which contains parsed XML config.
Also uses VLM to verify the UI interaction via trajectory.
"""

import json
import os
import tempfile
import logging
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_configure_ldap_auth(traj, env_info, task_info):
    """
    Verify LDAP configuration task.
    
    Criteria:
    1. LDAP setting 'corporate-ldap' exists (20 pts)
    2. Configuration values match expected (65 pts total)
    3. VLM verification of UI interaction (15 pts)
    """
    copy_from_env = env_info.get('copy_from_env')
    query_vlm = env_info.get('query_vlm')
    
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    
    # ==========================================================================
    # 1. Retrieve Programmatic Result
    # ==========================================================================
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {
            "passed": False, 
            "score": 0, 
            "feedback": f"Failed to retrieve task result: {str(e)}"
        }
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)
            
    score = 0
    feedback_parts = []
    
    # Check if target config was found
    if not result.get('found', False):
        return {
            "passed": False,
            "score": 0,
            "feedback": "LDAP setting 'corporate-ldap' was not found in Artifactory configuration."
        }
    
    score += 20
    feedback_parts.append("LDAP setting created")
    
    config = result.get('config', {})
    
    # ==========================================================================
    # 2. Check Configuration Values (65 pts)
    # ==========================================================================
    
    # Helper for string comparison (case-insensitive where appropriate)
    def check_field(field_name, actual, expected, points):
        # Boolean normalization
        if isinstance(expected, bool):
            actual_bool = str(actual).lower() == 'true'
            if actual_bool == expected:
                return points, f"{field_name} correct"
            return 0, f"{field_name} incorrect (expected {expected}, got {actual})"
        
        # String normalization
        if str(actual).strip() == str(expected).strip():
            return points, f"{field_name} correct"
        return 0, f"{field_name} incorrect (expected '{expected}', got '{actual}')"

    # URL (15 pts)
    p, msg = check_field("LDAP URL", config.get('ldapUrl'), metadata.get('expected_url'), 15)
    score += p
    feedback_parts.append(msg)
    
    # Search Filter (10 pts)
    p, msg = check_field("Search Filter", config.get('searchFilter'), metadata.get('expected_search_filter'), 10)
    score += p
    feedback_parts.append(msg)
    
    # Search Base (10 pts)
    p, msg = check_field("Search Base", config.get('searchBase'), metadata.get('expected_search_base'), 10)
    score += p
    feedback_parts.append(msg)
    
    # Manager DN (10 pts)
    p, msg = check_field("Manager DN", config.get('managerDn'), metadata.get('expected_manager_dn'), 10)
    score += p
    feedback_parts.append(msg)
    
    # Auto Create User (10 pts)
    p, msg = check_field("Auto Create Users", config.get('autoCreateUser'), metadata.get('expected_auto_create'), 10)
    score += p
    feedback_parts.append(msg)
    
    # Search Subtree (5 pts)
    p, msg = check_field("Search Subtree", config.get('searchSubTree'), metadata.get('expected_search_subtree'), 5)
    score += p
    feedback_parts.append(msg)
    
    # Email Attribute (5 pts)
    p, msg = check_field("Email Attribute", config.get('emailAttribute'), metadata.get('expected_email_attr'), 5)
    score += p
    feedback_parts.append(msg)

    # ==========================================================================
    # 3. VLM Verification (15 pts)
    # ==========================================================================
    vlm_score = 0
    vlm_feedback = ""
    
    if query_vlm:
        frames = sample_trajectory_frames(traj, n=4)
        final_shot = get_final_screenshot(traj)
        images = frames + ([final_shot] if final_shot else [])
        
        if images:
            prompt = """
            Review these screenshots of a user configuring JFrog Artifactory.
            
            Look for:
            1. The "LDAP Settings" or "Security" configuration page.
            2. A form being filled out with LDAP details (URL, Search Base, etc.).
            3. The user saving the configuration.
            
            Did the agent navigate to the LDAP configuration section and attempt to configure it?
            Answer Yes/No and briefly explain.
            """
            
            try:
                response = query_vlm(images=images, prompt=prompt).get('response', '').lower()
                if "yes" in response:
                    vlm_score = 15
                    vlm_feedback = "VLM verified UI workflow."
                else:
                    vlm_feedback = "VLM did not observe LDAP configuration steps."
            except Exception as e:
                vlm_feedback = f"VLM check failed: {e}"
        else:
            vlm_feedback = "No screenshots available for VLM."
    else:
        # Fallback if VLM not available but config is perfect
        if score >= 80:
            vlm_score = 15
            vlm_feedback = "VLM bypassed (high programmatic score)."
            
    score += vlm_score
    feedback_parts.append(vlm_feedback)
    
    # Final feedback formatting
    feedback = "; ".join(feedback_parts)
    
    return {
        "passed": score >= 60,
        "score": score,
        "feedback": feedback
    }