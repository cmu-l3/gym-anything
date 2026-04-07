#!/usr/bin/env python3
"""
Verifier for secure_mongodb_auth task.

Evaluation Criteria:
1. MongoDB Auth Enabled (25 pts) - Unauthenticated queries are rejected.
2. DB User Created (20 pts) - Authenticated query succeeds with requested credentials.
3. Config Files Updated (25 pts) - All 4 microservices have correct credentials.
4. Services Running (15 pts) - All 4 microservices are online in PM2.
5. Successful Connection (15 pts) - No MongoDB auth errors in the recent PM2 logs.
"""

import os
import json
import logging
import tempfile

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_secure_mongodb_auth(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_user = metadata.get('expected_mongo_user', 'socioboard')
    expected_pass = metadata.get('expected_mongo_pass', 'SecureMongo2026!')
    required_services = metadata.get('services', ['user', 'feeds', 'publish', 'notification'])

    # Copy result JSON from container
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    score = 0
    feedback_parts = []
    
    # 1. MongoDB Auth Enabled
    unauth_output = result.get('unauth_output', '').lower()
    unauth_exit = result.get('unauth_exit_code', 0)
    
    auth_enabled = False
    if unauth_exit != 0 and ('auth' in unauth_output or 'requires authentication' in unauth_output or 'unauthorized' in unauth_output):
        auth_enabled = True
        score += 25
        feedback_parts.append("MongoDB auth correctly enabled")
    else:
        feedback_parts.append("MongoDB auth NOT enabled (unauthenticated access permitted)")

    # 2. Database User Created
    auth_output = result.get('auth_output', '').lower()
    auth_exit = result.get('auth_exit_code', 1)
    
    if auth_exit == 0 and 'authentication failed' not in auth_output and 'bad auth' not in auth_output:
        score += 20
        feedback_parts.append("Database user successfully created and authenticated")
    else:
        feedback_parts.append("Failed to authenticate with requested credentials")

    # 3. Config Files Updated
    configs = result.get('configs', {})
    correct_configs = 0
    for svc in required_services:
        svc_config = configs.get(svc, {})
        mongo_config = {}
        
        # Search dict for mongo object
        for k, v in svc_config.items():
            if isinstance(v, dict) and 'mongo' in k.lower():
                mongo_config = v
                break
                
        if mongo_config.get('username') == expected_user and mongo_config.get('password') == expected_pass:
            correct_configs += 1
            
    if correct_configs == len(required_services):
        score += 25
        feedback_parts.append("All 4 microservice configs updated")
    elif correct_configs > 0:
        score += int(25 * (correct_configs / len(required_services)))
        feedback_parts.append(f"Only {correct_configs}/{len(required_services)} microservice configs updated")
    else:
        feedback_parts.append("Microservice configs NOT updated with new credentials")

    # 4. Services Running
    pm2_jlist = result.get('pm2_jlist', [])
    online_services = 0
    
    for process in pm2_jlist:
        name = process.get('name', '')
        status = process.get('pm2_env', {}).get('status', '')
        
        # Check if the process name roughly matches our required services
        if any(req in name for req in required_services) and status == 'online':
            online_services += 1
            
    # Cap at the required number in case there are duplicated pm2 processes
    online_services = min(online_services, len(required_services))
    
    if online_services == len(required_services):
        score += 15
        feedback_parts.append("All 4 PM2 services are online")
    else:
        score += int(15 * (online_services / len(required_services)))
        feedback_parts.append(f"Only {online_services}/{len(required_services)} PM2 services are online")

    # 5. Successful Connection (No PM2 log errors)
    pm2_logs = result.get('pm2_logs', '').lower()
    auth_errors = ['mongoservererror: bad auth', 'authentication failed', 'auth failed']
    
    has_auth_errors = any(err in pm2_logs for err in auth_errors)
    if not has_auth_errors and correct_configs == len(required_services) and auth_enabled:
        score += 15
        feedback_parts.append("No MongoDB authentication errors in PM2 logs")
    elif has_auth_errors:
        feedback_parts.append("Found MongoDB authentication errors in PM2 logs")
    else:
        # If configs weren't updated or auth wasn't enabled, don't give points for lack of errors
        feedback_parts.append("Skipped log check due to missing auth/config")

    # Determine Pass/Fail (Must have successfully locked down Mongo AND updated configs)
    passed = score >= 70 and auth_enabled and (correct_configs == len(required_services))

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }