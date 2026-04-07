#!/usr/bin/env python3
import json
import os
import tempfile
import logging
from typing import Dict, Any

# Assuming gym_anything provides these utilities in the environment
try:
    from gym_anything.vlm import query_vlm, get_final_screenshot, sample_trajectory_frames
except ImportError:
    # Fallback/Mock for local testing if needed
    def query_vlm(prompt, image, images=None):
        return {"success": False, "error": "ImportError"}
    def get_final_screenshot(traj):
        return None
    def sample_trajectory_frames(traj, n):
        return []

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_configure_ldap_attributes(traj, env_info, task_info):
    """
    Verifies that the agent configured LDAP attributes correctly in ADAudit Plus.
    
    Criteria:
    1. 'Office Location' custom label is visible/configured (Primary).
    2. 'department' and 'title' attributes are enabled.
    3. UI shows successful save/configuration state.
    """
    
    # 1. Retrieve result JSON from the Windows guest
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Infrastructure error: copy_from_env missing"}

    results_data = {}
    temp_json = tempfile.NamedTemporaryFile(delete=False, suffix=".json")
    try:
        # The path in the guest is C:\workspace\evidence\task_result.json
        # copy_from_env handles Windows paths if the agent supports it, otherwise might need adaptation
        # Standard gym_anything usually handles path conversion or expects linux-style paths for mounts
        # If it's a VM, we usually use the path defined in export_result.ps1
        copy_from_env("C:\\workspace\\evidence\\task_result.json", temp_json.name)
        with open(temp_json.name, 'r') as f:
            results_data = json.load(f)
    except Exception as e:
        logger.warning(f"Could not load task_result.json: {e}")
    finally:
        if os.path.exists(temp_json.name):
            os.unlink(temp_json.name)

    # 2. VLM Verification
    # We use the final screenshot captured by the framework (traj) OR the one exported by the script.
    # Framework screenshot is safer against spoofing.
    
    frames = sample_trajectory_frames(traj, n=3)
    final_img = get_final_screenshot(traj)
    
    if not final_img:
        return {"passed": False, "score": 0, "feedback": "No screenshots available for verification"}

    images_to_check = frames + [final_img]
    
    prompt = """
    You are verifying an IT configuration task in ManageEngine ADAudit Plus.
    
    Goal: The user should have configured 'LDAP Attributes' settings.
    
    Please look for a table or list of attributes.
    Check for these specific details:
    1. Is there an attribute named 'physicalDeliveryOfficeName' visible?
    2. Is the Display Name for 'physicalDeliveryOfficeName' set to 'Office Location'? (CRITICAL)
    3. Are the attributes 'department' and 'title' checked, enabled, or present in the configured list?
    4. Is there any success message (e.g., "Settings saved successfully")?
    
    Return JSON:
    {
        "page_is_ldap_config": boolean,
        "office_location_label_found": boolean,
        "department_enabled": boolean,
        "title_enabled": boolean,
        "success_message_visible": boolean,
        "confidence": "low|medium|high"
    }
    """
    
    vlm_result = query_vlm(prompt=prompt, images=images_to_check)
    
    score = 0
    feedback = []
    
    # DB Check (Bonus/Confirmation)
    if results_data.get("db_string_found"):
        score += 30
        feedback.append("Database confirmation: 'Office Location' string found in config.")
    
    # VLM Evaluation
    if vlm_result.get("success"):
        parsed = vlm_result.get("parsed", {})
        
        if parsed.get("page_is_ldap_config"):
            score += 10
            feedback.append("Navigated to LDAP Config page.")
            
        if parsed.get("office_location_label_found"):
            score += 40
            feedback.append("Success: 'Office Location' label verified visually.")
        else:
            feedback.append("Failed: 'Office Location' label not seen in screenshots.")
            
        if parsed.get("department_enabled"):
            score += 10
            feedback.append("Attribute 'department' verified.")
            
        if parsed.get("title_enabled"):
            score += 10
            feedback.append("Attribute 'title' verified.")
            
    else:
        feedback.append("VLM analysis failed.")

    # Pass logic
    # Must have the custom label (40 pts) and either DB confirmation OR valid UI navigation
    passed = (score >= 60) and ("Office Location" in str(feedback))

    return {
        "passed": passed,
        "score": min(score, 100),
        "feedback": " | ".join(feedback)
    }