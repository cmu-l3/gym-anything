#!/usr/bin/env python3
"""
Verifier for configure_https_console task.
"""

import json
import os
import tempfile
import logging
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_configure_https_console(traj, env_info, task_info):
    """
    Verify HTTPS configuration for EventLog Analyzer.
    
    Criteria:
    1. Marker file exists and created during task (5 pts)
    2. HTTPS port 8443 is accessible and responds to requests (30 pts)
    3. SSL Handshake succeeds (confirms it's actually SSL) (20 pts)
    4. Config files show evidence of update (15 pts)
    5. VLM verification of UI navigation (30 pts)
    
    Pass threshold: 65 points AND HTTPS must be accessible.
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
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback_parts = []
    
    # 1. Marker File (5 pts)
    if result.get('marker_exists') and result.get('marker_created_during_task'):
        content = result.get('marker_content', '').strip()
        if content == 'HTTPS_ENABLED:8443':
            score += 5
            feedback_parts.append("Marker file created correctly")
        else:
            score += 2
            feedback_parts.append(f"Marker file exists but content wrong: '{content}'")
    else:
        feedback_parts.append("Marker file missing")

    # 2. HTTPS Connectivity (30 pts) - CRITICAL
    https_ok = result.get('https_accessible', False)
    if https_ok:
        score += 30
        feedback_parts.append("HTTPS port 8443 accessible")
    else:
        feedback_parts.append("HTTPS port 8443 NOT accessible")

    # 3. SSL Handshake (20 pts)
    if result.get('ssl_handshake_success', False):
        score += 20
        feedback_parts.append("SSL handshake successful")
    elif https_ok:
        feedback_parts.append("Port open but SSL handshake failed")

    # 4. Configuration File (15 pts)
    conf_score = 0
    if result.get('conf_updated'):
        conf_score += 5
    if result.get('conf_port_8443'):
        conf_score += 5
    if result.get('conf_ssl_enabled'):
        conf_score += 5
    
    score += conf_score
    if conf_score > 0:
        feedback_parts.append(f"Config file updated ({conf_score}/15 pts)")

    # 5. VLM Verification (30 pts)
    # Check if agent navigated to settings and interacted with SSL config
    frames = sample_trajectory_frames(traj, n=6)
    final_frame = get_final_screenshot(traj)
    all_frames = frames + [final_frame] if final_frame else frames
    
    vlm_prompt = """
    You are verifying an agent configuring HTTPS/SSL for ManageEngine EventLog Analyzer.
    
    Look at the sequence of screenshots. Did the agent:
    1. Navigate to a 'Settings' or 'Admin' area?
    2. Access 'Connection Settings', 'Web Server Settings', or 'System Settings'?
    3. Interact with an SSL/HTTPS checkbox or radio button?
    4. Change a port number (likely to 8443)?
    5. Restart the server or see a restart notification?
    
    Also, in the final frames, does the browser show a 'Warning: Potential Security Risk' 
    (common for self-signed certs) or a secure HTTPS lock icon?
    
    Respond in JSON:
    {
        "settings_navigated": boolean,
        "ssl_config_seen": boolean,
        "https_evidence_in_browser": boolean,
        "score": number (0-30 based on evidence of workflow)
    }
    """
    
    vlm_score = 0
    try:
        vlm_result = query_vlm(images=all_frames, prompt=vlm_prompt)
        if vlm_result and vlm_result.get('success'):
            parsed = vlm_result.get('parsed', {})
            vlm_score = parsed.get('score', 0)
            
            # Sanity check VLM score
            if vlm_score > 30: vlm_score = 30
            if vlm_score < 0: vlm_score = 0
            
            feedback_parts.append(f"VLM verification: {vlm_score}/30 pts")
            
            if parsed.get('settings_navigated'):
                feedback_parts.append("(VLM: Settings navigated)")
            if parsed.get('ssl_config_seen'):
                feedback_parts.append("(VLM: SSL config seen)")
        else:
            feedback_parts.append("VLM verification failed (fallback)")
            # Fallback points if programmatic checks passed strongly
            if https_ok and conf_score > 10:
                vlm_score = 20
    except Exception as e:
        logger.error(f"VLM error: {e}")
        # Fallback
        if https_ok: 
            vlm_score = 15
            
    score += vlm_score

    # Final Evaluation
    # Pass if score >= 65 AND HTTPS is actually working
    passed = (score >= 65) and https_ok

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }