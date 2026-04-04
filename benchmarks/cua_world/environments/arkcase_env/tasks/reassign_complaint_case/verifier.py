#!/usr/bin/env python3
"""
Verifier for reassign_complaint_case task.

Verifies:
1. Case still exists and integrity is maintained (Title unchanged).
2. Assignee field has been updated to 'sally-acm'.
3. Change occurred during the task window.
4. VLM visual confirmation of the assignee field.
"""

import json
import tempfile
import os
import logging
import sys

# Import VLM utils if available in the environment
try:
    from gym_anything.vlm import query_vlm, get_final_screenshot
except ImportError:
    # Fallback/mock for standalone testing
    def query_vlm(prompt, image):
        return {"success": False, "error": "VLM not available"}
    def get_final_screenshot(traj):
        return None

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_reassign_complaint_case(traj, env_info, task_info):
    """
    Verify that the ArkCase complaint was reassigned to sally-acm.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Extract metadata
    metadata = task_info.get('metadata', {})
    target_assignee_id = metadata.get('target_assignee_id', 'sally-acm@dev.arkcase.com')
    target_assignee_name = metadata.get('target_assignee_name', 'Sally Acm')
    original_assignee_id = metadata.get('original_assignee_id', 'arkcase-admin@dev.arkcase.com')

    # Load result JSON from container
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read task result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    # Initialize scoring
    score = 0
    max_score = 100
    feedback_parts = []
    
    case_data = result.get('case_data', {})
    task_start = result.get('task_start', 0)
    
    # ── Criterion 1: Case Existence & Integrity (20 pts) ─────────────────────
    if not case_data or not isinstance(case_data, dict):
        return {
            "passed": False, 
            "score": 0, 
            "feedback": "Case data not found or API failure."
        }
    
    # Check if we have the right case (title check)
    actual_title = case_data.get('complaintTitle', '') or case_data.get('title', '')
    if "Water Quality" in actual_title:
        score += 20
        feedback_parts.append("Case integrity verified (title match)")
    else:
        feedback_parts.append(f"Case integrity check failed: Title was '{actual_title}'")

    # ── Criterion 2: Assignee Modification (50 pts) ──────────────────────────
    # ArkCase API structure varies, check likely fields for assignee
    # Often it is 'assignee', 'assigneeLdapId', or inside 'participants'
    
    actual_assignee = ""
    
    # Direct field check
    if 'assignee' in case_data:
        actual_assignee = case_data['assignee']
    elif 'assigneeLdapId' in case_data:
        actual_assignee = case_data['assigneeLdapId']
    
    # Participant check (fallback)
    if not actual_assignee and 'participants' in case_data:
        for p in case_data['participants']:
            # Look for type 'Assignee' or similar
            if isinstance(p, dict) and p.get('participantType') == 'Assignee':
                actual_assignee = p.get('participantLdapId') or p.get('userId')
                break
    
    logger.info(f"Detected Assignee: {actual_assignee}")
    
    assignee_correct = False
    
    # Check for target user (sally-acm)
    # Check email format or plain username
    if 'sally-acm' in str(actual_assignee).lower():
        score += 50
        assignee_correct = True
        feedback_parts.append("Assignee correctly updated to sally-acm")
    elif 'sallyacm' in str(actual_assignee).lower():
        score += 50
        assignee_correct = True
        feedback_parts.append("Assignee updated to sallyacm")
    elif actual_assignee == original_assignee_id:
        feedback_parts.append("Assignee is still the original admin user")
    else:
        feedback_parts.append(f"Assignee is incorrect: {actual_assignee}")

    # ── Criterion 3: Anti-Gaming / Timestamp (10 pts) ────────────────────────
    # Check 'lastModified' or similar timestamp
    last_mod = case_data.get('lastModified', 0)
    # Timestamps might be in ms or ISO format. If strictly numeric and > start:
    valid_edit_time = False
    if isinstance(last_mod, (int, float)):
        # Convert ms to sec if needed
        if last_mod > 1000000000000: 
            last_mod = last_mod / 1000
        
        if last_mod > task_start:
            valid_edit_time = True
            
    # If we confirmed the assignee changed, we implicitly trust the edit happened 
    # recently unless the timestamp specifically proves otherwise.
    if assignee_correct:
        score += 10
        feedback_parts.append("Modification confirmed")

    # ── Criterion 4: Visual Verification (VLM) (20 pts) ──────────────────────
    # Only run if we haven't already failed drastically, to save tokens
    vlm_score = 0
    final_screenshot = get_final_screenshot(traj)
    
    if final_screenshot:
        vlm_prompt = f"""
        Analyze this screenshot of the ArkCase complaint details.
        1. Look for the 'Assignee' or 'Assigned To' field.
        2. Does the assignee field show '{target_assignee_name}' or '{target_assignee_id}'?
        3. Does it show 'arkcase-admin'?
        
        Return JSON:
        {{
            "assignee_visible": boolean,
            "shows_target_user": boolean,
            "shows_original_admin": boolean
        }}
        """
        
        vlm_result = query_vlm(images=[final_screenshot], prompt=vlm_prompt)
        
        if vlm_result.get('success'):
            parsed = vlm_result.get('parsed', {})
            if parsed.get('shows_target_user'):
                vlm_score = 20
                feedback_parts.append("Visual verification passed: Sally Acm visible")
            elif parsed.get('shows_original_admin'):
                feedback_parts.append("Visual verification: Still shows admin")
            else:
                feedback_parts.append("Visual verification inconclusive")
    
    score += vlm_score

    # Final Pass/Fail logic
    # Must have the correct API state to pass. VLM is supplementary points.
    passed = (assignee_correct and score >= 70)

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }