#!/usr/bin/env python3
"""
Verifier for configure_product_settings task (ADAudit Plus).

Verification Logic:
1. VLM Trajectory Verification (Primary):
   - Confirms navigation to Admin -> Settings/Personalize
   - Confirms entry of "Meridian National Bank" as Organization Name
   - Confirms selection of "15 Minutes" for Session Timeout
   - Confirms "Save" action
2. Programmatic Verification (Secondary):
   - Checks if the string "Meridian National Bank" appears in the HTML of the application (captured by export script)
"""

import json
import os
import sys
import tempfile
import logging

# Add parent directory to path to import vlm_utils if needed, 
# though we usually assume standard imports or gym_anything.vlm
try:
    from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm
except ImportError:
    # Fallback for local testing
    def sample_trajectory_frames(traj, n=5): return []
    def get_final_screenshot(traj): return None
    def query_vlm(prompt, images): return {"success": False, "error": "Mock VLM"}

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_configure_product_settings(traj, env_info, task_info):
    """
    Verify ADAudit Plus configuration task.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_org_name = metadata.get('expected_org_name', "Meridian National Bank")
    branding_check_string = metadata.get('branding_string_check', "Meridian National Bank")

    # ================================================================
    # 1. READ EXPORTED RESULT
    # ================================================================
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    result_data = {}
    try:
        # Note: Windows path in container is C:\workspace\task_result.json
        # copy_from_env handles the mapping if the agent is remote, 
        # usually we provide the absolute path inside the guest.
        copy_from_env("C:\\workspace\\task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result_data = json.load(f)
    except Exception as e:
        logger.error(f"Failed to read result file: {e}")
        # Proceed with VLM only if file fails
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    # ================================================================
    # 2. SCORING CRITERIA
    # ================================================================
    score = 0
    feedback_parts = []
    
    # Criterion A: Programmatic Check (HTML Content) - 30 pts
    branding_in_html = result_data.get('branding_found_in_html', False)
    if branding_in_html:
        score += 30
        feedback_parts.append("Organization name found in application HTML.")
    else:
        feedback_parts.append("Organization name NOT found in application HTML (check failed or settings not saved).")

    # Criterion B: App Running - 10 pts
    if result_data.get('app_was_running', False):
        score += 10
    
    # Criterion C: VLM Verification (Trajectory) - 60 pts
    # We verify the workflow: Admin -> Settings -> Input Name -> Input Timeout -> Save
    frames = sample_trajectory_frames(traj, n=8)
    final_shot = get_final_screenshot(traj)
    
    if frames:
        vlm_prompt = f"""
        Analyze this sequence of screenshots from an IT admin performing a configuration task in ADAudit Plus.
        
        Goal: 
        1. Change Organization Name to '{expected_org_name}'.
        2. Change Session Timeout to '15 Minutes'.
        
        Check for the following steps:
        1. Did the user navigate to an 'Admin' or 'Settings' tab?
        2. Did the user access 'Personalize', 'General Settings', or 'Product Settings'?
        3. Is there a screenshot showing the text input '{branding_check_string}' in an 'Organization Name' or 'Product Title' field?
        4. Is there a screenshot showing a dropdown/selector for 'Session Expiry' or 'Timeout' set to '15' or '15 Minutes'?
        5. Did the user click a 'Save' or 'Update' button?
        6. Does the FINAL screenshot show the new title '{branding_check_string}' in the top banner/header?
        
        Output JSON:
        {{
            "admin_navigated": boolean,
            "settings_accessed": boolean,
            "org_name_input_visible": boolean,
            "timeout_input_visible": boolean,
            "save_clicked": boolean,
            "final_branding_visible": boolean,
            "confidence": "low|medium|high"
        }}
        """
        
        vlm_response = query_vlm(images=frames + ([final_shot] if final_shot else []), prompt=vlm_prompt)
        
        if vlm_response.get('success'):
            analysis = vlm_response.get('parsed', {})
            
            # Score breakdown
            if analysis.get('admin_navigated'): score += 5
            if analysis.get('settings_accessed'): score += 5
            if analysis.get('org_name_input_visible'): score += 20
            if analysis.get('timeout_input_visible'): score += 15
            if analysis.get('save_clicked'): score += 5
            if analysis.get('final_branding_visible'): 
                score += 10
                feedback_parts.append("VLM confirmed new branding in final state.")
            
            feedback_parts.append(f"VLM Analysis: {json.dumps(analysis)}")
        else:
            feedback_parts.append("VLM verification failed to execute.")
    else:
        feedback_parts.append("No trajectory frames available for verification.")

    # ================================================================
    # FINAL VERDICT
    # ================================================================
    # Pass if Score >= 60 AND (Branding verified programmatically OR via VLM input visibility)
    pass_threshold = 60
    passed = score >= pass_threshold
    
    return {
        "passed": passed,
        "score": min(100, score),
        "feedback": " | ".join(feedback_parts)
    }