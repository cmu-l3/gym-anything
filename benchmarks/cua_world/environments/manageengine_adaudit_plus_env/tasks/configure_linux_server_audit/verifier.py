#!/usr/bin/env python3
"""
Verifier for configure_linux_server_audit task.

Strategy:
1. Primary: VLM verification of the final evidence screenshot.
   - Checks if 'bastion01' is visible in a server list.
   - Checks if the interface looks like ADAudit Plus Linux settings.
2. Secondary: Check if the configuration string was found in backend files (via export_result).
3. Tertiary: Basic file evidence (screenshot exists).
"""

import json
import os
import sys
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def build_vlm_prompt():
    return """
You are auditing a computer security task. The user was asked to add a new Linux server named 'bastion01' to ManageEngine ADAudit Plus.

Examine the provided screenshot.
1. Do you see a list of servers or workstations?
2. Is there an entry for "bastion01" (or "bastion01" IP 192.168.1.100)?
3. Does the interface appear to be the "Configured Server(s)" or "Linux Audit" section of ADAudit Plus?
4. Is there any status indicator (e.g., "Down", "Connection Failed")? (Note: Failure is expected/allowed).

Answer in JSON:
{
    "server_list_visible": true/false,
    "bastion01_found": true/false,
    "interface_match": true/false,
    "status_observation": "string description",
    "confidence": "high/medium/low"
}
"""

def verify_configure_linux_server_audit(traj, env_info, task_info):
    """
    Verifies that the Linux server 'bastion01' was added to configuration.
    """
    copy_from_env = env_info.get('copy_from_env')
    query_vlm = env_info.get('query_vlm')
    
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System error: copy_from_env missing"}

    # 1. Retrieve Result JSON from Container
    local_result_path = tempfile.mktemp(suffix=".json")
    try:
        # Note: Container path is Windows style, but copy_from_env handles abstract paths usually.
        # If running on Linux host verifying Windows container, paths might need care.
        # Assuming the framework handles the path translation or we use the absolute path defined in export.
        copy_from_env("C:\\workspace\\task_result.json", local_result_path)
        with open(local_result_path, 'r') as f:
            result_data = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Could not retrieve task result: {str(e)}"}
    finally:
        if os.path.exists(local_result_path):
            os.remove(local_result_path)

    score = 0
    feedback = []

    # 2. Check File Evidence (20 points)
    if result_data.get("screenshot_exists"):
        score += 10
        feedback.append("Evidence screenshot captured.")
    else:
        feedback.append("No evidence screenshot found.")

    if result_data.get("found_in_config_file"):
        score += 20
        feedback.append("Configuration verified in backend files.")
    
    # 3. VLM Verification (60 points)
    # We retrieve the specific screenshot taken by the user (evidence) OR the final state
    # The export script saved evidence to C:\workspace\linux_audit_evidence.png
    
    evidence_path = tempfile.mktemp(suffix=".png")
    vlm_success = False
    
    try:
        copy_from_env("C:\\workspace\\linux_audit_evidence.png", evidence_path)
        
        if query_vlm:
            vlm_response = query_vlm(prompt=build_vlm_prompt(), image=evidence_path)
            vlm_parsed = vlm_response.get('parsed', {})
            
            if vlm_parsed.get('bastion01_found'):
                score += 60
                vlm_success = True
                feedback.append("VLM confirmed 'bastion01' is listed in the UI.")
            elif vlm_parsed.get('server_list_visible'):
                score += 10
                feedback.append("VLM saw server list but 'bastion01' was missing/unclear.")
            else:
                feedback.append("VLM did not verify the server addition.")
        else:
            feedback.append("VLM unavailable for visual verification.")
            
    except Exception as e:
        feedback.append(f"Could not retrieve/analyze screenshot: {str(e)}")
    finally:
        if os.path.exists(evidence_path):
            os.remove(evidence_path)

    # 4. Trajectory Fallback (if screenshot was bad but config was found)
    # If we found it in config (strong signal) but VLM failed (maybe bad screenshot), we bump score
    if result_data.get("found_in_config_file") and not vlm_success:
        score += 40
        feedback.append("Backend config confirms success despite visual check failure.")

    # 5. Final Threshold
    # Pass if score >= 70 (Must have either Config or VLM confirmation + Screenshot)
    passed = score >= 70
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }