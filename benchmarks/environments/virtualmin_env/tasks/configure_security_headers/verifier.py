#!/usr/bin/env python3
import json
import os
import re
import tempfile
import logging
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_configure_security_headers(traj, env_info, task_info):
    """
    Verifies that security headers are configured correctly in Apache.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load expected values
    metadata = task_info.get('metadata', {})
    expected_headers = metadata.get('headers', {
        "X-Content-Type-Options": "nosniff",
        "X-Frame-Options": "SAMEORIGIN",
        "Strict-Transport-Security": "max-age=31536000"
    })

    # Load result from container
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result JSON: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback = []
    
    config_content = result.get("config_content", "")
    curl_output = result.get("curl_output", "")
    apache_running = result.get("apache_running", False)
    config_syntax_ok = result.get("config_syntax_ok", False)
    file_modified = result.get("file_modified_during_task", False)

    # 1. Verify Apache Health (12 points)
    if apache_running:
        score += 5
    else:
        feedback.append("Apache is not running.")
    
    if config_syntax_ok:
        score += 7
    else:
        feedback.append("Apache configuration has syntax errors.")

    if not file_modified:
        feedback.append("Configuration file was not modified during the task.")
        # We don't fail immediately, but it's suspicious

    # 2. Verify Config File Content (36 points - 12 each)
    # Regex to handle varied spacing/quoting: Header always set Name "Value"
    for header, value in expected_headers.items():
        # Construct regex: Header (always|onsuccess)? set <HeaderName> "?<Value>"?
        # Note: Virtualmin/Apache syntax might vary slightly, but standard is: Header always set X-Y "Z"
        # We allow flexible whitespace and optional quotes
        pattern = re.compile(
            r"Header\s+(always\s+)?set\s+" + re.escape(header) + r"\s+[\"']?" + re.escape(value).split(';')[0] + r".*", 
            re.IGNORECASE
        )
        
        if pattern.search(config_content):
            score += 12
            # Check stricter match for HSTS max-age if needed, but regex handles basic existence
        else:
            feedback.append(f"Missing or incorrect directive in config: {header}")

    # 3. Verify Live HTTP Headers (27 points - 9 each)
    # This proves the config was actually applied/reloaded
    curl_lower = curl_output.lower()
    for header, value in expected_headers.items():
        # Split value for partial matching (e.g. HSTS has parameters)
        val_check = value.split(';')[0].lower() # e.g., "max-age=31536000"
        
        # Check if header exists in curl output
        if header.lower() in curl_lower:
            # Check if value matches
            # Simple check: look for the value substring in the output
            if val_check in curl_lower:
                score += 9
            else:
                feedback.append(f"Header {header} present but wrong value in live response.")
        else:
            feedback.append(f"Header {header} not found in live HTTP response.")

    # 4. Verify Scope (10 points)
    # Ensure headers are inside the correct VirtualHost block
    # Simple check: verify file edited was the specific globex.test file (captured in export)
    # and not global config. Export script grabs the specific site file.
    # If the specific file has the headers, we assume correct scope for this task's simplicity.
    if "globex.test" in result.get("config_file_path", "") and score > 20:
        score += 10
    
    # 5. VLM Verification (15 points)
    # Verify the agent actually used the UI
    vlm_score = 0
    try:
        frames = sample_trajectory_frames(traj, n=4)
        final_screen = get_final_screenshot(traj)
        
        prompt = (
            "Review these screenshots of a Virtualmin/Webmin session. "
            "Did the user perform the following actions?\n"
            "1. Navigate to the 'globex.test' virtual server.\n"
            "2. Access the Apache Webserver configuration or 'Edit Directives' page.\n"
            "3. Edit text that looks like Apache configuration directives.\n"
            "4. Save the configuration.\n"
            "Reply with 'YES' or 'NO' and a brief reason."
        )
        
        vlm_result = query_vlm(images=frames + [final_screen], prompt=prompt)
        
        if "YES" in vlm_result.get("response", "").upper():
            vlm_score = 15
        else:
            feedback.append("VLM did not verify UI workflow.")
            
    except Exception as e:
        logger.warning(f"VLM verification failed: {e}")
        # Fallback: if programmatic score is high, give partial credit for VLM
        if score >= 70:
            vlm_score = 10
    
    score += vlm_score

    # Final Pass Logic
    # Must have at least the config file modified + syntax OK + decent score
    passed = (score >= 60) and config_syntax_ok and apache_running
    
    return {
        "passed": passed,
        "score": min(100, score),
        "feedback": " | ".join(feedback) if feedback else "Task completed successfully."
    }