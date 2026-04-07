#!/usr/bin/env python3
"""
Verifier for configure_agent_settings task.

Verification Strategy:
1. File Existence Check:
   - Verifies `agent_settings_summary.txt` exists and contains "8555".
   - Verifies `agent_settings_evidence.png` exists and was created during the task.
2. VLM Verification (Visual):
   - Inspects the agent-provided screenshot OR the final trajectory frame.
   - Checks for "Agent Port" value (8555).
   - Checks for "Install Agent Automatically" (unchecked).
   - Checks for "Upgrade Agents Automatically" (unchecked).
"""

import json
import os
import tempfile
import logging
from gym_anything.vlm import query_vlm, get_final_screenshot

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_configure_agent_settings(traj, env_info, task_info):
    """
    Verify the agent configuration task using file evidence and VLM.
    """
    # 1. Setup and Resource Acquisition
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System error: copy_from_env not available"}

    metadata = task_info.get('metadata', {})
    expected_port = metadata.get('expected_port', "8555")
    
    score = 0
    feedback_parts = []
    
    # 2. Retrieve Result JSON from Container
    temp_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("C:\\workspace\\task_result.json", temp_json.name)
        with open(temp_json.name, 'r') as f:
            result_data = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve task results: {str(e)}"}
    finally:
        if os.path.exists(temp_json.name):
            os.unlink(temp_json.name)

    # 3. Verify Text Summary (Programmatic Check)
    # Worth 20 points
    summary_content = result_data.get('summary_content', '').strip()
    if result_data.get('summary_exists') and expected_port in summary_content:
        score += 20
        feedback_parts.append("Summary file correct.")
    elif result_data.get('summary_exists'):
        score += 10
        feedback_parts.append(f"Summary file exists but content '{summary_content}' does not match '{expected_port}'.")
    else:
        feedback_parts.append("Summary file missing.")

    # 4. Verify Evidence Screenshot Existence (Anti-Gaming)
    # Worth 10 points
    evidence_path_local = None
    if result_data.get('evidence_exists') and result_data.get('evidence_valid_time'):
        score += 10
        feedback_parts.append("Evidence screenshot created.")
        
        # Download the evidence screenshot for VLM analysis
        temp_img = tempfile.NamedTemporaryFile(delete=False, suffix='.png')
        try:
            copy_from_env("C:\\workspace\\agent_settings_evidence.png", temp_img.name)
            evidence_path_local = temp_img.name
        except Exception:
            logger.warning("Could not download evidence screenshot despite existence report.")
    else:
        feedback_parts.append("Evidence screenshot missing or old.")

    # 5. VLM Verification (Visual Check of Settings)
    # Worth 70 points total
    # We prefer the agent's screenshot if available (it captures the specific moment), 
    # otherwise fallback to final trajectory frame.
    
    image_to_check = evidence_path_local
    if not image_to_check:
        image_to_check = get_final_screenshot(traj)
        feedback_parts.append("Using final screen state for verification.")

    if image_to_check:
        prompt = f"""
        Analyze this screenshot of the ManageEngine ADAudit Plus Agent Settings page.
        
        I need to verify three specific settings:
        1. **Agent Port**: Look for a text field labeled 'Agent Port'. Does it contain the value '{expected_port}'?
        2. **Auto Install**: Look for a checkbox labeled 'Install Agent Automatically' or similar. Is it UNCHECKED (disabled)?
        3. **Auto Upgrade**: Look for a checkbox labeled 'Upgrade Agents Automatically' or similar. Is it UNCHECKED (disabled)?
        
        Return a JSON object with the following boolean keys:
        - "port_correct": true if port is {expected_port}
        - "install_disabled": true if auto-install is unchecked
        - "upgrade_disabled": true if auto-upgrade is unchecked
        - "settings_visible": true if you can clearly see the settings form
        """
        
        vlm_resp = query_vlm(
            prompt=prompt,
            image=image_to_check,
            response_model={
                "properties": {
                    "port_correct": {"type": "boolean"},
                    "install_disabled": {"type": "boolean"},
                    "upgrade_disabled": {"type": "boolean"},
                    "settings_visible": {"type": "boolean"}
                },
                "required": ["port_correct", "install_disabled", "upgrade_disabled", "settings_visible"]
            }
        )
        
        # Process VLM response
        if vlm_resp:
            # Clean up VLM dict if needed
            vlm_data = vlm_resp if isinstance(vlm_resp, dict) else {}
            
            if vlm_data.get('settings_visible'):
                # Port (30 points)
                if vlm_data.get('port_correct'):
                    score += 30
                    feedback_parts.append("Agent Port configured correctly.")
                else:
                    feedback_parts.append("Agent Port incorrect or not visible.")

                # Install Checkbox (20 points)
                if vlm_data.get('install_disabled'):
                    score += 20
                    feedback_parts.append("Auto-install disabled.")
                else:
                    feedback_parts.append("Auto-install enabled (should be disabled).")

                # Upgrade Checkbox (20 points)
                if vlm_data.get('upgrade_disabled'):
                    score += 20
                    feedback_parts.append("Auto-upgrade disabled.")
                else:
                    feedback_parts.append("Auto-upgrade enabled (should be disabled).")
            else:
                feedback_parts.append("Could not verify settings: Form not clearly visible in screenshot.")
        else:
            feedback_parts.append("Visual verification failed (VLM error).")
            
        # Cleanup temp image
        if evidence_path_local and os.path.exists(evidence_path_local):
            os.unlink(evidence_path_local)
    else:
        feedback_parts.append("No suitable screenshot available for verification.")

    # 6. Final Evaluation
    # Pass threshold: 70 points (Must get port right + some other criteria)
    passed = score >= 70
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback_parts)
    }