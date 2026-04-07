#!/usr/bin/env python3
"""
Verifier for configure_domain_admin_alert task.

Verification Strategy:
1. Hybrid approach using Database checks (if successful) and VLM (Visual) checks.
2. The Database check looks for the specific Alert Profile and Filter in Postgres.
3. The VLM check looks at the trajectory to confirm the agent interacted with 
   Advanced Filters and typed "Domain Admins".
"""

import json
import os
import sys
import tempfile
import logging
from typing import Dict, Any

# Add parent directory for shared utilities if needed
# sys.path.insert(0, str(Path(__file__).parent.parent))
# from vlm_utils import ... 

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_configure_domain_admin_alert(traj, env_info, task_info):
    """
    Verify the configuration of the Domain Admin alert.
    """
    # 1. Setup and Load Results
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load the JSON result exported by the PowerShell script
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    task_result = {}
    try:
        # The export script saves to C:\workspace\tasks\...\task_result.json
        # We need to map this to the container path.
        # Assuming the standard mapping for this environment allows access.
        # If the path in the script is absolute Windows path, we need to know how `copy_from_env` handles it.
        # Usually `copy_from_env` takes a path inside the container/VM.
        # The Windows path "C:\workspace\..." usually maps to the root or specific mount.
        # We will try the path defined in export_result.ps1
        
        copy_from_env("C:\\workspace\\tasks\\configure_domain_admin_alert\\task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            task_result = json.load(f)
    except Exception as e:
        logger.warning(f"Could not load task_result.json: {e}")
        # Proceeding to VLM verification if DB export failed
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    # 2. Scoring Variables
    score = 0
    max_score = 100
    feedback = []
    
    # Metadata for expectations
    metadata = task_info.get('metadata', {})
    expected_profile = metadata.get('expected_profile_name', 'Critical - Domain Admin Addition')
    
    # 3. Database Verification Signal (Primary if available)
    db_profile_found = task_result.get('profile_found_in_db', False)
    db_filter_found = task_result.get('filter_found_in_db', False)
    
    if db_profile_found:
        score += 30
        feedback.append(f"SUCCESS: Alert Profile '{expected_profile}' found in database.")
    else:
        feedback.append("WARNING: Alert Profile not found in database export (could be DB access issue).")

    if db_filter_found:
        score += 30
        feedback.append("SUCCESS: Specific filter for 'Domain Admins' found in database.")
    elif db_profile_found:
        feedback.append("FAILURE: Alert Profile found but 'Domain Admins' filter criteria not detected in DB.")

    # 4. VLM Verification Signal (Crucial for UI interaction)
    # We need to check if the user actually set the filter in the UI
    from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm
    
    frames = sample_trajectory_frames(traj, n=4)
    final_shot = get_final_screenshot(traj)
    images_to_check = frames + [final_shot] if final_shot else frames
    
    if not images_to_check:
        return {"passed": False, "score": 0, "feedback": "No screenshots available for verification."}

    vlm_prompt = f"""
    You are verifying if a user configured a specific security alert in ADAudit Plus.
    
    GOAL: Create an Alert Profile named "{expected_profile}" that triggers ONLY for the "Domain Admins" group.
    
    Look at the screenshots for these specific steps:
    1. Did the user enter "{expected_profile}" as the Name?
    2. Did the user select "Group Management" or "Member Added to Group"?
    3. CRITICAL: Did the user click "Advanced Configuration" or the "+" filter icon?
    4. CRITICAL: Did the user type "Domain Admins" into a "Group Name" filter field?
    5. Did the user enter "soc@bank-corp.com" for email?
    
    Return JSON:
    {{
        "profile_name_correct": boolean,
        "filter_domain_admins_seen": boolean,
        "email_configured": boolean,
        "severity_critical": boolean,
        "confidence": "low|medium|high"
    }}
    """
    
    try:
        vlm_res = query_vlm(images=images_to_check, prompt=vlm_prompt)
        vlm_data = vlm_res.get('parsed', {})
        
        # Score VLM findings
        if vlm_data.get('profile_name_correct'):
            score += 10
            feedback.append("VLM: Verified correct profile name entered.")
            
        if vlm_data.get('filter_domain_admins_seen'):
            score += 20 
            feedback.append("VLM: Verified 'Domain Admins' filter was applied.")
            # If DB check failed but VLM saw it clearly, we award partial points for the filter
            if not db_filter_found: 
                 score += 10 # Backup points
        
        if vlm_data.get('email_configured'):
            score += 10
            feedback.append("VLM: Verified email recipient configured.")
            
    except Exception as e:
        feedback.append(f"VLM analysis failed: {e}")

    # 5. Final Threshold Check
    # Pass if: (DB confirmed Profile AND Filter) OR (VLM confirmed Profile AND Filter)
    # Filter is the key differentiator from a generic alert.
    
    filter_confirmed = db_filter_found or vlm_data.get('filter_domain_admins_seen', False)
    profile_confirmed = db_profile_found or vlm_data.get('profile_name_correct', False)
    
    passed = (score >= 70) and filter_confirmed and profile_confirmed
    
    if not filter_confirmed:
        feedback.append("CRITICAL FAILURE: Could not verify that the alert was filtered specifically for 'Domain Admins'.")
        
    return {
        "passed": passed,
        "score": min(score, 100),
        "feedback": " | ".join(feedback)
    }