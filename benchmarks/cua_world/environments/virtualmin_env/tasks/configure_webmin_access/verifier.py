#!/usr/bin/env python3
import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_configure_webmin_access(traj, env_info, task_info):
    """
    Verify that Webmin IP access control is configured correctly.
    Criteria:
    1. Access control is enabled (allow= line exists).
    2. Localhost (127.0.0.1) is allowed.
    3. Admin VPN (10.8.0.42) is allowed.
    4. User is not locked out (curl test passed).
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    score = 0
    max_score = 100
    feedback_parts = []
    
    # 1. Get JSON result
    task_result = {}
    temp_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_json.name)
        with open(temp_json.name, 'r') as f:
            task_result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load task result: {str(e)}"}
    finally:
        if os.path.exists(temp_json.name):
            os.unlink(temp_json.name)

    # 2. Get Config File content
    config_content = ""
    temp_config = tempfile.NamedTemporaryFile(delete=False, suffix='.conf')
    try:
        copy_from_env("/tmp/miniserv.conf.result", temp_config.name)
        with open(temp_config.name, 'r') as f:
            config_content = f.read()
    except Exception as e:
        # If config file missing, score 0
        pass
    finally:
        if os.path.exists(temp_config.name):
            os.unlink(temp_config.name)

    # Parse config
    allow_line = None
    deny_line = None
    
    for line in config_content.splitlines():
        if line.strip().startswith("allow="):
            allow_line = line.strip().split("=", 1)[1]
        if line.strip().startswith("deny="):
            deny_line = line.strip().split("=", 1)[1]

    # --- Scoring Criteria ---

    # Criterion 1: Access Control Enabled (30 pts)
    if allow_line is not None:
        score += 30
        feedback_parts.append("Access control enabled")
        allowed_ips = allow_line.split()
    else:
        feedback_parts.append("Access control NOT enabled (no 'allow=' line)")
        allowed_ips = []

    # Criterion 2: Localhost Allowed (30 pts)
    if "127.0.0.1" in allowed_ips:
        score += 30
        feedback_parts.append("Localhost allowed")
    else:
        feedback_parts.append("Localhost (127.0.0.1) missing from allow list")

    # Criterion 3: Admin VPN Allowed (30 pts)
    if "10.8.0.42" in allowed_ips:
        score += 30
        feedback_parts.append("Admin VPN allowed")
    else:
        feedback_parts.append("Admin VPN (10.8.0.42) missing from allow list")

    # Criterion 4: Connectivity Maintained (10 pts)
    # Note: If 127.0.0.1 is missing, they are locked out, so this double-penalizes slightly,
    # but it's a distinct operational check.
    locked_out = task_result.get("locked_out", True)
    if not locked_out:
        score += 10
        feedback_parts.append("Connectivity verified")
    else:
        feedback_parts.append("User is locked out (Webmin unreachable from localhost)")

    # Anti-gaming check
    if not task_result.get("config_modified", False):
        score = 0
        feedback_parts = ["Configuration file was not modified during task"]

    passed = (score == 100)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }