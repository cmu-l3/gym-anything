#!/usr/bin/env python3
"""
Verifier for legacy_app_network_aliases task.

Verification Criteria:
1. App Container Running (30 pts): The legacy-app container must be in 'running' state.
2. Network Aliases Configured (60 pts):
   - Postgres has alias 'db.inventory.local' (20 pts)
   - Redis has alias 'cache.inventory.local' (20 pts)
   - Mock-Auth has alias 'auth.provider.external' (20 pts)
3. Application Logs (10 pts): Logs must contain the success message "All systems go! Application started."

Pass Threshold: 90 points (All aliases must be working for the app to function properly).
"""

import json
import tempfile
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_legacy_app_network_aliases(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load result from container
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
    
    # 1. Check if App is Running (30 pts)
    if result.get('app_running', False):
        score += 30
        feedback_parts.append("App container is running")
    else:
        feedback_parts.append("App container is NOT running")

    # 2. Check Aliases (60 pts total)
    aliases_correct = 0
    
    if result.get('db_alias_correct', False):
        score += 20
        aliases_correct += 1
        feedback_parts.append("DB alias correct")
    else:
        feedback_parts.append("DB alias missing/wrong")
        
    if result.get('redis_alias_correct', False):
        score += 20
        aliases_correct += 1
        feedback_parts.append("Redis alias correct")
    else:
        feedback_parts.append("Redis alias missing/wrong")
        
    if result.get('auth_alias_correct', False):
        score += 20
        aliases_correct += 1
        feedback_parts.append("Auth alias correct")
    else:
        feedback_parts.append("Auth alias missing/wrong")

    # 3. Check Logs for Success Message (10 pts)
    app_logs = result.get('app_logs', "")
    success_msg = "All systems go! Application started."
    if success_msg in app_logs:
        score += 10
        feedback_parts.append("App logs confirm successful startup")
    else:
        feedback_parts.append("App logs do not show success message")

    # Bonus check: DNS resolution (confirmation only, points included in alias check)
    if result.get('dns_check_success', False):
        feedback_parts.append("(DNS resolution verified inside container)")

    # Pass threshold
    passed = score >= 90

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts),
        "details": {
            "aliases_found": aliases_correct,
            "app_running": result.get('app_running', False),
            "log_snippet": app_logs[-200:] if app_logs else "No logs"
        }
    }