#!/usr/bin/env python3
"""
Verifier for configure_console_ip_restrictions task.
"""

import json
import tempfile
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_configure_console_ip_restrictions(traj, env_info, task_info):
    """
    Verify IP restriction configuration.
    
    Criteria:
    1. Console must still be accessible from localhost (Critical).
    2. Trusted Host feature must be enabled in DB.
    3. 127.0.0.1 must be in allowed list.
    4. 10.20.30.40 must be in allowed list.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load result
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback = []
    
    # 1. Check Accessibility (Critical)
    # If they locked themselves out, max score is 10 (for effort?), or 0.
    is_accessible = result.get('accessible', False)
    if is_accessible:
        score += 10
        feedback.append("Console remains accessible from localhost.")
    else:
        feedback.append("CRITICAL: Console is NOT accessible from localhost. You locked yourself out!")
        return {"passed": False, "score": 0, "feedback": " | ".join(feedback)}

    # 2. Check Feature Enabled
    # We look for known keys in system_config. 
    # The key might be 'enable_trusted_host' or similar. We search loosely.
    config = result.get('system_config', {})
    feature_enabled = False
    
    # Look for keys like 'start.trustedhost', 'enable_trusted_host', etc. set to 'true'
    for k, v in config.items():
        if 'trusted' in k.lower() and 'host' in k.lower():
            if v.lower() == 'true' or v == '1':
                feature_enabled = True
                feedback.append(f"Found enabled setting: {k}={v}")
                break
    
    # Fallback: if trusted_hosts_raw has data, feature might be effectively enabled or we assume enabled if list exists
    trusted_hosts = result.get('trusted_hosts_raw', [])
    if not feature_enabled and len(trusted_hosts) > 0:
        # Some versions might not have a global toggle, just the presence of rows
        feature_enabled = True
        feedback.append("Trusted hosts table populated (implies feature active).")

    if feature_enabled:
        score += 30
        feedback.append("Trusted Host feature is enabled.")
    else:
        feedback.append("Trusted Host feature does not appear to be enabled.")

    # 3. Check Required IPs
    # We check if the raw strings in trusted_hosts contain our IPs.
    # The raw lines might be formatted like "1|127.0.0.1" or just "127.0.0.1".
    
    localhost_found = False
    jumpbox_found = False
    
    required_localhost = "127.0.0.1"
    required_jumpbox = "10.20.30.40"
    
    for row in trusted_hosts:
        if required_localhost in row:
            localhost_found = True
        if required_jumpbox in row:
            jumpbox_found = True
            
    if localhost_found:
        score += 30
        feedback.append(f"{required_localhost} found in allow list.")
    else:
        feedback.append(f"MISSING: {required_localhost} not found in allow list.")

    if jumpbox_found:
        score += 30
        feedback.append(f"{required_jumpbox} found in allow list.")
    else:
        feedback.append(f"MISSING: {required_jumpbox} not found in allow list.")

    # Calculate final status
    passed = (score >= 100)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }