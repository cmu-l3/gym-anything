#!/usr/bin/env python3
"""
Verifier for configure_external_pacs_node task in Weasis.

Uses a combination of:
1. Programmatic state verification: checking modified XML config files.
2. Anti-gaming file checks: timestamp and existence checks.
3. VLM Trajectory checking: to ensure the GUI was actually used to configure the node.
"""

import os
import sys
import json
import logging
import tempfile

# Add gym_anything VLM utilities
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '../../', 'utils'))
try:
    from gym_anything.vlm import query_vlm, sample_trajectory_frames, get_final_screenshot
except ImportError:
    # Handle standalone execution gracefully if not in full env
    pass

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

VLM_PROMPT = """You are evaluating an AI agent's performance in a DICOM medical viewer (Weasis).
The agent was asked to add a new DICOM Query/Retrieve node in the Preferences with these details:
- Description: Regional_Partner_PACS
- AE Title: REGIONAL_ARCHIVE
- IP/Hostname: 10.99.50.200
- Port: 11112

Look at the provided trajectory frames (screenshots). 
1. Is the Preferences/Settings dialog for DICOM Nodes visible in any frame?
2. Can you clearly see the text 'REGIONAL_ARCHIVE' entered in a field or table?
3. Can you clearly see the IP '10.99.50.200' and Port '11112' entered?

Respond ONLY with a valid JSON object matching this schema:
{
    "preferences_dialog_visible": true/false,
    "ae_title_visible": true/false,
    "ip_and_port_visible": true/false
}
"""

def verify_configure_pacs_node(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    feedback_parts = []
    score = 0
    max_score = 100
    
    # 1. Retrieve the programmatic task results
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result JSON: {e}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    # 2. Check Screenshot Artifact (20 points)
    screenshot_exists = result.get('screenshot_exists', False)
    screenshot_valid_mtime = result.get('screenshot_valid_mtime', False)
    screenshot_size = result.get('screenshot_size', 0)
    
    if screenshot_exists and screenshot_size > 5000:
        if screenshot_valid_mtime:
            score += 20
            feedback_parts.append("Screenshot saved correctly during task.")
        else:
            feedback_parts.append("Screenshot exists but timestamp is invalid (gaming suspected).")
    else:
        feedback_parts.append("Expected screenshot pacs_node_config.png not found or empty.")

    # 3. Check Persistence in Configuration File (40 points)
    # This proves the agent actually clicked "Apply/Save" and didn't just type it and leave.
    config_file_found = result.get('config_file_found', False)
    node_content = result.get('node_config_content', '').upper()
    
    expected_ip = task_info.get('metadata', {}).get('expected_ip', '10.99.50.200').upper()
    expected_port = task_info.get('metadata', {}).get('expected_port', '11112').upper()
    expected_aet = task_info.get('metadata', {}).get('expected_aet', 'REGIONAL_ARCHIVE').upper()

    config_valid = False
    if config_file_found:
        has_aet = expected_aet in node_content
        has_ip = expected_ip in node_content
        has_port = expected_port in node_content
        
        if has_aet and has_ip and has_port:
            score += 40
            config_valid = True
            feedback_parts.append("Config file updated successfully with new node params.")
        else:
            feedback_parts.append("Config file found but missing IP, Port, or AET.")
    else:
        feedback_parts.append("Node configuration was not saved to disk (did you apply/close?).")

    # 4. VLM Trajectory Verification (40 points)
    # Even if they didn't save the config, did they do the UI work?
    try:
        frames = sample_trajectory_frames(traj, n=5)
        final = get_final_screenshot(traj)
        all_frames = frames + [final] if final else frames
        
        if not all_frames:
            feedback_parts.append("No trajectory frames available for VLM.")
        else:
            vlm_response = query_vlm(images=all_frames, prompt=VLM_PROMPT)
            
            if vlm_response and vlm_response.get("success"):
                parsed = vlm_response.get("parsed", {})
                
                vlm_score = 0
                if parsed.get("preferences_dialog_visible"):
                    vlm_score += 10
                if parsed.get("ae_title_visible"):
                    vlm_score += 15
                if parsed.get("ip_and_port_visible"):
                    vlm_score += 15
                
                score += vlm_score
                if vlm_score == 40:
                    feedback_parts.append("VLM verified correct GUI configuration state.")
                else:
                    feedback_parts.append(f"VLM partial/failed verification ({vlm_score}/40 pts).")
            else:
                feedback_parts.append("VLM query failed or returned invalid response.")
    except Exception as e:
        logger.error(f"VLM verification error: {e}")
        feedback_parts.append("VLM verification skipped due to error.")

    # 5. Final pass determination
    # Must achieve at least 80 points total (Requires saving the file AND VLM UI verification, or screenshot + config)
    passed = score >= 80

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }