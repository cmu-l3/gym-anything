#!/usr/bin/env python3
"""
Verifier for update_oauth_config_production task.

Evaluates:
1. Valid JSON Syntax for all four config files (critical).
2. Domain replacements (localhost -> app.socioboard.com) across targeted URL fields.
3. Exact Client ID rotation in the user microservice.
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def scan_urls(obj, state):
    """
    Recursively scans JSON object for URL keys and flags presence of local/prod domains.
    Only checks keys containing 'url', 'callback', or 'redirect' to avoid false positives (e.g. DB hosts).
    """
    if isinstance(obj, dict):
        for k, v in obj.items():
            if isinstance(v, str):
                key_lower = k.lower()
                if 'url' in key_lower or 'callback' in key_lower or 'redirect' in key_lower:
                    if 'localhost' in v:
                        state['has_localhost'] = True
                    if 'app.socioboard.com' in v:
                        state['has_production'] = True
            else:
                scan_urls(v, state)
    elif isinstance(obj, list):
        for item in obj:
            scan_urls(item, state)

def get_client_id(obj):
    """Recursively searches for google_api -> client_id."""
    if isinstance(obj, dict):
        if 'google_api' in obj and isinstance(obj['google_api'], dict):
            if 'client_id' in obj['google_api']:
                return obj['google_api']['client_id']
        for k, v in obj.items():
            res = get_client_id(v)
            if res:
                return res
    elif isinstance(obj, list):
        for item in obj:
            res = get_client_id(item)
            if res:
                return res
    return None

def verify_update_oauth_config(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    target_client_id = metadata.get('target_google_client_id', '5544332211-prod.apps.googleusercontent.com')

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

    start_time = result.get('task_start_time', 0)
    services_data = result.get('services', {})
    
    score = 0
    feedback_parts = []
    all_json_valid = True

    # 1. JSON Validity Check (20 points)
    valid_count = 0
    parsed_services = {}
    
    for svc in ['user', 'feeds', 'publish', 'notification']:
        svc_info = services_data.get(svc, {})
        if not svc_info.get('exists'):
            feedback_parts.append(f"{svc} config missing")
            all_json_valid = False
            continue
            
        content = svc_info.get('content', '')
        try:
            parsed = json.loads(content)
            parsed_services[svc] = parsed
            valid_count += 1
        except json.JSONDecodeError:
            feedback_parts.append(f"{svc} JSON is invalid/broken")
            all_json_valid = False

    if valid_count == 4:
        score += 20
        feedback_parts.append("All configs contain valid JSON (+20)")

    # Early exit if JSON is completely broken, since the app would crash
    if not all_json_valid and valid_count == 0:
        return {
            "passed": False,
            "score": 0,
            "feedback": "All JSON files are broken/unparsable. Critical Failure."
        }

    # 2. Check Service URLs (15 points per service)
    # 3. Check specific Google Client ID in User Service (20 points)
    
    for svc in ['user', 'feeds', 'publish', 'notification']:
        if svc not in parsed_services:
            continue
            
        parsed = parsed_services[svc]
        svc_info = services_data[svc]
        
        # Anti-gaming: Ensure file was modified
        if svc_info['mtime'] < start_time:
            feedback_parts.append(f"{svc} config was not modified")
            continue
            
        state = {'has_localhost': False, 'has_production': False}
        scan_urls(parsed, state)
        
        # Verify domain replacement
        if state['has_production'] and not state['has_localhost']:
            score += 15
            feedback_parts.append(f"{svc} URLs correctly updated (+15)")
        elif state['has_localhost']:
            feedback_parts.append(f"{svc} still contains localhost URLs")
        elif not state['has_production']:
            feedback_parts.append(f"{svc} missing production URLs")

        # Verify Google Client ID (User service only)
        if svc == 'user':
            found_client_id = get_client_id(parsed)
            if found_client_id == target_client_id:
                score += 20
                feedback_parts.append("Google client_id updated correctly (+20)")
            else:
                feedback_parts.append(f"Google client_id incorrect (found: {found_client_id})")

    passed = score >= 70 and all_json_valid

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }