#!/usr/bin/env python3
"""
Verifier for harden_apache_global_config task.

Criteria:
1. Live ServerTokens check (Server header == "Apache") - 25 pts
2. Live ServerSignature check (No version in 404 page) - 25 pts
3. Live TraceEnable check (TRACE method returns 403/405) - 25 pts
4. Configuration persistence (Directives found in config files) - 15 pts
5. VLM verification (Agent used UI) - 10 pts
"""

import json
import tempfile
import os
import logging
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_harden_apache_global_config(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Retrieve result JSON
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
    
    # 1. ServerTokens (Live)
    server_header = result.get("server_header", "").strip()
    # Expected: "Server: Apache" exactly (no version)
    if server_header == "Server: Apache":
        score += 25
        feedback_parts.append("ServerTokens: Pass (Header hidden)")
    elif "Apache" in server_header and "/" not in server_header:
        # Lenient check
        score += 25
        feedback_parts.append("ServerTokens: Pass")
    else:
        feedback_parts.append(f"ServerTokens: Fail (Header is '{server_header}')")

    # 2. ServerSignature (Live)
    signature_visible = result.get("signature_visible", True)
    if not signature_visible:
        score += 25
        feedback_parts.append("ServerSignature: Pass (Hidden on error pages)")
    else:
        feedback_parts.append("ServerSignature: Fail (Version visible on error pages)")

    # 3. TraceEnable (Live)
    trace_code = str(result.get("trace_http_code", "200"))
    if trace_code in ["403", "405"]:
        score += 25
        feedback_parts.append(f"TraceEnable: Pass (Method blocked: {trace_code})")
    elif trace_code == "200":
        feedback_parts.append("TraceEnable: Fail (TRACE method allowed 200 OK)")
    else:
        # Some other error, technically secure but maybe broken?
        score += 20
        feedback_parts.append(f"TraceEnable: Partial (Unexpected code {trace_code})")

    # 4. Configuration Persistence (Config Files)
    # Check if directives exist in file (grep output from script)
    config_tokens = result.get("config_tokens_found", "")
    config_sig = result.get("config_signature_found", "")
    config_trace = result.get("config_trace_found", "")
    config_modified = result.get("config_modified_during_task", False)

    config_score = 0
    if config_tokens: config_score += 5
    if config_sig: config_score += 5
    if config_trace: config_score += 5
    
    # Bonus for modifying the file during the task
    if config_modified and config_score > 0:
        feedback_parts.append("Config: Updated successfully")
    elif config_score < 15:
         feedback_parts.append("Config: Missing some directives in file")
    
    score += config_score

    # 5. VLM Verification (Visual Check)
    # Ensure they used the UI (Webmin/Virtualmin) and didn't just SSH/sed
    frames = sample_trajectory_frames(traj, n=4)
    final = get_final_screenshot(traj)
    
    vlm_prompt = """
    Review these screenshots of a user configuring an Apache server.
    1. Is the user interacting with the Webmin or Virtualmin web interface?
    2. Do you see settings related to "Server Tokens", "Server Signature", or "Trace Enable"?
    3. Is the user editing Apache configuration files via the web UI?
    """
    
    vlm_result = query_vlm(images=frames + [final], prompt=vlm_prompt)
    
    # We award points if the VLM thinks the user interacted with the UI
    # This is a soft check to encourage UI usage as per task desc, but 
    # if the technical checks pass perfectly, we don't fail them completely.
    vlm_score = 10
    if "webmin" in vlm_result.get("response", "").lower() or "virtualmin" in vlm_result.get("response", "").lower():
        score += vlm_score
    else:
        # Fallback: if they got 90 points (everything else perfect), give them the 10
        if score >= 90:
            score += vlm_score

    # Final tally
    passed = score >= 70
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }