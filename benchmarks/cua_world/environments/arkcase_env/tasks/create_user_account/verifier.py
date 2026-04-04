#!/usr/bin/env python3
"""
Verifier for create_user_account task in ArkCase.

Verification Strategy:
1. Validates that the user exists in the LDAP backend (Samba AD).
2. Checks correct attributes: First Name, Last Name, Email.
3. Checks correct Group Membership (ACM_INVESTIGATOR_DEV).
4. Confirms user is recognized by ArkCase API.
5. Uses VLM to verify UI workflow (Navigation to Admin panel).
"""

import json
import tempfile
import os
import logging
from gym_anything.vlm import sample_trajectory_frames, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_create_user_account(traj, env_info, task_info):
    """
    Verify the creation of user elena.rodriguez via LDAP query and UI evidence.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}
        
    metadata = task_info.get('metadata', {})
    expected = metadata.get('expected_user', {})
    
    # Load Result JSON
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result file: {str(e)}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)
            
    score = 0
    feedback_parts = []
    
    # 1. Check User Existence (25 pts)
    if result.get('ldap_user_exists', False):
        score += 25
        feedback_parts.append("✅ User created in LDAP")
    else:
        feedback_parts.append("❌ User NOT found in LDAP")
        return {"passed": False, "score": 0, "feedback": "User was not created."}

    # 2. Check Attributes (25 pts total)
    attrs = result.get('ldap_attributes', {})
    
    # First Name
    if attrs.get('givenName') == expected.get('first_name'):
        score += 15
        feedback_parts.append("✅ First Name correct")
    else:
        feedback_parts.append(f"❌ First Name mismatch (Expected: {expected.get('first_name')}, Got: {attrs.get('givenName')})")

    # Last Name (Check only if First Name check ran, but score independently)
    if attrs.get('sn') == expected.get('last_name'):
        # Implicit point share or strict check? JSON says 15 for name correct generally,
        # but let's split logically if we want granular feedback.
        # Metadata scoring says "name_correct: 15". Let's assume the previous 15 covers both or split.
        # Let's keep the previous 15 for givenName and add logic here.
        # Actually metadata says: user_exists: 25, name_correct: 15, email_correct: 10
        # I assigned 15 to givenName above. Let's adjust.
        # Let's do: givenName (8), sn (7).
        pass # Already credited full 15 for first name above? No, let's fix scoring logic.
        
    # Correct Scoring Logic based on Metadata
    # Reset score to 25 (User Exists)
    score = 25 
    
    # Name (15 pts)
    name_score = 0
    if attrs.get('givenName') == expected.get('first_name'):
        name_score += 8
    if attrs.get('sn') == expected.get('last_name'):
        name_score += 7
    score += name_score
    if name_score < 15:
         feedback_parts.append(f"⚠️ Name mismatch: {attrs.get('givenName')} {attrs.get('sn')}")
    else:
         feedback_parts.append("✅ Name correct")

    # Email (10 pts)
    if attrs.get('mail') == expected.get('email'):
        score += 10
        feedback_parts.append("✅ Email correct")
    else:
        feedback_parts.append(f"❌ Email mismatch (Got: {attrs.get('mail')})")

    # 3. Check Group Membership (20 pts)
    if result.get('group_membership', {}).get('is_member', False):
        score += 20
        feedback_parts.append(f"✅ User in group {expected.get('group')}")
    else:
        feedback_parts.append(f"❌ User NOT in group {expected.get('group')}")

    # 4. API Verification (15 pts)
    if result.get('api_verification', {}).get('user_found', False):
        score += 15
        feedback_parts.append("✅ ArkCase API recognizes user")
    else:
        feedback_parts.append("❌ ArkCase API did not return user details")

    # 5. VLM UI Workflow Verification (15 pts)
    # Check if agent visited Admin panel
    frames = sample_trajectory_frames(traj, n=4)
    if not frames:
        feedback_parts.append("⚠️ No trajectory frames for VLM check")
    else:
        vlm_prompt = (
            "Does this sequence of images show a user navigating to an Administration or User Management panel "
            "and filling out a user creation form? Look for 'User Management', 'Create User', or 'New User' buttons/forms."
        )
        vlm_res = query_vlm(frames, vlm_prompt)
        
        if vlm_res.get('success') and vlm_res.get('parsed', {}).get('answer', False): # assuming boolean or positive sentiment
             # Since generic query_vlm might return text, let's look for keywords if strict bool not returned
             resp_text = str(vlm_res.get('response', '')).lower()
             if "yes" in resp_text or "admin" in resp_text or "form" in resp_text:
                 score += 15
                 feedback_parts.append("✅ UI Admin workflow confirmed")
             else:
                 score += 5 # Partial credit if they did the work but VLM is unsure
                 feedback_parts.append("❓ UI workflow unclear from screenshots")
        else:
             # Fallback if VLM fails or says no
             # If API/LDAP is perfect, they might have used CLI or API directly.
             # If score is already high, give partial points to avoid false negatives.
             if score >= 70:
                 score += 5
                 feedback_parts.append("⚠️ UI workflow skipped or not detected")

    return {
        "passed": score >= 60,
        "score": min(score, 100),
        "feedback": " | ".join(feedback_parts)
    }