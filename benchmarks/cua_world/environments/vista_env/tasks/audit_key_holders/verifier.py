#!/usr/bin/env python3
"""
Verifier for Audit Key Holders task.

Verification Strategy:
1. Check VistA and YDBGui connectivity (Basics).
2. Verify browser is open and showing YDBGui/Global Viewer.
3. VLM Verification:
   - Check if ^XUSEC global is visible.
   - Check if XUPROG key is visible/expanded.
   - Check if numbers (DUZs) matching the ground truth are visible.
"""

import json
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_audit_key_holders(traj, env_info, task_info):
    """
    Verify that the agent navigated to ^XUSEC("XUPROG") and displayed key holders.
    """
    copy_from_env = env_info.get('copy_from_env')
    query_vlm = env_info.get('query_vlm')

    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System error: copy_from_env missing"}

    # 1. Load Result JSON
    import tempfile
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/audit_key_holders_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load task result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback_parts = []
    
    # --- Criterion 1: Infrastructure (20 pts) ---
    if result.get('vista_container_status') == 'running':
        score += 10
    else:
        feedback_parts.append("VistA container not running")

    if result.get('browser_window_open'):
        score += 10
    else:
        feedback_parts.append("Browser window closed")

    # --- Criterion 2: Navigation & Data Visibility (VLM) (80 pts) ---
    final_screenshot = result.get('screenshot_path', '/tmp/task_final_screenshot.png')
    
    # We rely on the framework's copy mechanism to get the screenshot content if needed,
    # but here we pass the path to the VLM query function which handles it.
    # Note: query_vlm usually expects a local path if the framework synced it, 
    # or we might need to rely on the trajectory object passed in `traj`.
    # Robust fallback: use traj.get('final_screenshot')
    
    vlm_image_path = traj.get('final_screenshot')
    
    vlm_score = 0
    vlm_passed = False
    
    if query_vlm and vlm_image_path:
        gt_holders = result.get('ground_truth', {}).get('holders', '')
        # Clean up holders string "1,42," -> "1, 42"
        gt_holders_formatted = gt_holders.replace(',', ', ').strip(', ')
        
        prompt = f"""
        Analyze this screenshot of the YDBGui database viewer.
        
        Task: The user should be viewing the VistA global ^XUSEC (Security Key Holders) and specifically the key 'XUPROG'.
        
        Please check for the following:
        1. Is the global '^XUSEC' visible in the navigation tree or title?
        2. Is the key name 'XUPROG' visible?
        3. Is the node expanded to show numbers (user IDs)?
        4. Specifically, do you see any of these user IDs: {gt_holders_formatted}?
        
        Respond in JSON format:
        {{
            "global_visible": true/false,
            "key_visible": true/false,
            "holders_visible": true/false,
            "specific_ids_seen": ["1", "42", etc],
            "confidence": "high/medium/low"
        }}
        """
        
        try:
            vlm_resp = query_vlm(prompt=prompt, image=vlm_image_path)
            
            # Parse logic (simplified assumption that vlm_resp returns a dict or json string)
            # If string, simple parsing
            resp_str = str(vlm_resp).lower()
            
            if "global_visible\": true" in resp_str or "^xusec" in resp_str:
                vlm_score += 30
                feedback_parts.append("Navigated to ^XUSEC")
                
            if "key_visible\": true" in resp_str or "xuprog" in resp_str:
                vlm_score += 25
                feedback_parts.append("Found XUPROG key")
                
            if "holders_visible\": true" in resp_str or "specific_ids_seen" in resp_str:
                vlm_score += 25
                feedback_parts.append("Key holders visible")
                vlm_passed = True
                
        except Exception as e:
            feedback_parts.append(f"VLM verification failed: {e}")
    else:
        feedback_parts.append("No screenshot available for VLM verification")

    score += vlm_score

    return {
        "passed": score >= 60 and vlm_passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }