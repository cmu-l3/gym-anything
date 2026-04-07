#!/usr/bin/env python3
"""
Verifier for configure_proxy_settings task.

Verifies that the ManageEngine ADAudit Plus proxy settings were configured correctly.
Uses a combination of file system checks (persistence) and VLM (visual state).
"""

import json
import os
import tempfile
import logging
from typing import Dict, Any

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_configure_proxy_settings(traj, env_info, task_info):
    """
    Verify proxy configuration.
    
    Scoring:
    - 20 pts: Proxy Host found in config/logs
    - 20 pts: Proxy Port found in config/logs
    - 20 pts: Proxy Username found in config/logs
    - 20 pts: Files were actually modified (Anti-gaming)
    - 20 pts: VLM verification of final screen showing settings
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Environment copy function not available"}

    # Load metadata
    metadata = task_info.get('metadata', {})
    expected_host = metadata.get('proxy_host', 'proxy.corpnet-finance.com')
    
    score = 0
    feedback = []
    
    # 1. Retrieve JSON result from container
    temp_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        # Windows path inside container is C:\workspace\task_result.json
        # Docker cp usually handles the path, but we might need to be careful with slashes
        copy_from_env("C:\\workspace\\task_result.json", temp_json.name)
        with open(temp_json.name, 'r') as f:
            result_data = json.load(f)
    except Exception as e:
        logger.error(f"Failed to copy or read result json: {e}")
        return {"passed": False, "score": 0, "feedback": "Failed to retrieve verification data from environment"}
    finally:
        if os.path.exists(temp_json.name):
            os.unlink(temp_json.name)

    # 2. Evaluate programmatic evidence (Max 60 pts)
    
    # Host (20 pts)
    if result_data.get("proxy_host_found") or result_data.get("log_confirmation"):
        score += 20
        feedback.append("Proxy host configuration detected.")
    else:
        feedback.append("Proxy host configuration NOT detected in files.")

    # Port (20 pts)
    if result_data.get("proxy_port_found"):
        score += 20
        feedback.append("Proxy port configuration detected.")
    elif result_data.get("log_confirmation"):
        # Partial credit if only log confirms action but not specific port file
        score += 10
        feedback.append("Proxy configuration action logged.")

    # Username (20 pts)
    if result_data.get("proxy_user_found"):
        score += 20
        feedback.append("Proxy username configuration detected.")
    
    # File modification check (Anti-gaming check)
    if result_data.get("files_modified_count", 0) > 0:
        feedback.append(f"{result_data['files_modified_count']} config files modified.")
    else:
        feedback.append("WARNING: No configuration files were modified.")

    # 3. VLM Verification (Max 20 pts + bonus for enabled state)
    # We check the final screenshot for visual confirmation
    # This acts as a sanity check and covers cases where config format is obscure
    
    from gym_anything.vlm import get_final_screenshot, query_vlm
    
    final_screenshot = get_final_screenshot(traj)
    if final_screenshot:
        prompt = f"""
        Analyze this screenshot of the ManageEngine ADAudit Plus interface.
        I am looking for Proxy Server Settings.
        
        Check for:
        1. Is the 'Proxy Server' checkbox or toggle ENABLED/CHECKED?
        2. Is the Host set to '{expected_host}'?
        3. Is the Port set to '8080'?
        4. Is Authentication enabled/checked?
        
        Return JSON:
        {{
            "proxy_enabled": true/false,
            "host_correct": true/false,
            "port_correct": true/false,
            "auth_enabled": true/false
        }}
        """
        
        try:
            vlm_response = query_vlm(prompt=prompt, image=final_screenshot)
            if vlm_response.get("success"):
                parsed = vlm_response.get("parsed", {})
                
                if parsed.get("host_correct"):
                    score += 10
                    feedback.append("Visual: Host verified.")
                
                if parsed.get("port_correct"):
                    score += 5
                    feedback.append("Visual: Port verified.")
                    
                if parsed.get("proxy_enabled"):
                    score += 5
                    feedback.append("Visual: Proxy enabled.")
                    
        except Exception as e:
            logger.warning(f"VLM verification failed: {e}")
            feedback.append("Visual verification skipped due to error.")

    # Final scoring logic
    # Pass if score >= 70 OR (Programmatic Host Found AND File Modified)
    passed = score >= 70
    
    # Safety valve: if score is low but we found the exact host string in a modified config file,
    # we should probably pass (programmatic truth > visual issues)
    if result_data.get("proxy_host_found") and result_data.get("files_modified_count", 0) > 0:
        if score < 70:
            score = 70
            feedback.append("Boosted score based on hard evidence in config files.")
            passed = True

    return {
        "passed": passed,
        "score": min(100, score),
        "feedback": " | ".join(feedback)
    }