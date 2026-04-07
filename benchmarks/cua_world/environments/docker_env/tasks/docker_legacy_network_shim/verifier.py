#!/usr/bin/env python3
"""
Verifier for docker_legacy_network_shim task.
"""

import json
import os
import tempfile
import logging

logger = logging.getLogger(__name__)

def verify_docker_legacy_network_shim(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Read result
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
    feedback = []

    # 1. Integrity Check (Critical - Penalty)
    if result.get('code_modified', False):
        return {
            "passed": False, 
            "score": 0, 
            "feedback": "FAILED: Application code (main.py) was modified. You must solve this via infrastructure configuration only."
        }

    # 2. Verify Database Alias (20 pts)
    # db_aliases is a dict of network_name -> network_config
    # network_config has "Aliases": [...]
    db_aliases_json = result.get('db_aliases', {})
    db_shim_found = False
    if db_aliases_json:
        for net_name, config in db_aliases_json.items():
            aliases = config.get('Aliases', [])
            if aliases and "db-primary.corp.local" in aliases:
                db_shim_found = True
                break
    
    if db_shim_found:
        score += 20
        feedback.append("Database alias configured correctly.")
    else:
        feedback.append("Database alias 'db-primary.corp.local' NOT found.")

    # 3. Verify Auth Alias (20 pts)
    auth_aliases_json = result.get('auth_aliases', {})
    auth_shim_found = False
    if auth_aliases_json:
        for net_name, config in auth_aliases_json.items():
            aliases = config.get('Aliases', [])
            if aliases and "auth-gateway.partner.net" in aliases:
                auth_shim_found = True
                break

    if auth_shim_found:
        score += 20
        feedback.append("Auth alias configured correctly.")
    else:
        feedback.append("Auth alias 'auth-gateway.partner.net' NOT found.")

    # 4. Verify Environment Variable (15 pts)
    app_env = result.get('app_env', [])
    mode_correct = False
    if app_env:
        for env_var in app_env:
            if env_var == "MODE=PRODUCTION":
                mode_correct = True
                break
    
    if mode_correct:
        score += 15
        feedback.append("Environment MODE=PRODUCTION set.")
    else:
        feedback.append("Environment MODE incorrect or missing.")

    # 5. Verify Log Persistence (Mounts) (20 pts)
    # Check if a mount exists where Destination is /var/log/fincore
    app_mounts = result.get('app_mounts', [])
    mount_found = False
    if app_mounts:
        for mount in app_mounts:
            if mount.get('Destination') == '/var/log/fincore':
                mount_found = True
                break
    
    # Also check if the file actually exists on host (proof it worked)
    log_exists = result.get('log_exists_on_host', False)

    if mount_found and log_exists:
        score += 20
        feedback.append("Log persistence configured and verified.")
    elif mount_found:
        score += 10
        feedback.append("Mount configured but log file not found on host (App crashed?).")
    else:
        feedback.append("Log volume mount missing.")

    # 6. Verify App Health (15 pts)
    if result.get('app_running', False):
        score += 15
        feedback.append("Application is running.")
    else:
        feedback.append("Application is NOT running.")

    # 7. Success Artifact Content (10 pts)
    log_content = result.get('log_content', "")
    if "SYSTEM_READY" in log_content:
        score += 10
        feedback.append("Application reported SYSTEM_READY.")
    
    passed = score >= 70
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }