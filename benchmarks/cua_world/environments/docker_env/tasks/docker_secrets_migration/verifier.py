#!/usr/bin/env python3
"""
Verifier for docker_secrets_migration task.

Scoring Criteria (Total 100):
- Secrets removed from Env/Cmd (40 pts total)
    - DB Env Clean: 10 pts
    - Cache Cmd Clean: 10 pts
    - API Env Clean (DB/Redis/Stripe): 15 pts
    - API Dockerfile Clean (Flask Secret): 5 pts
- Configuration Correctness (20 pts total)
    - Secrets directory populated: 10 pts
    - Compose file defines secrets: 10 pts
- Functionality (30 pts total)
    - All containers running: 15 pts
    - API responds 200 OK with JSON: 15 pts
- Documentation (10 pts total)
    - Report exists and has content: 10 pts

Pass Threshold: 60 pts
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_secrets_migration(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Retrieve result file
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read task result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback = []

    # 1. Check Secrets Removal (40 pts)
    audit = result.get('secrets_audit', {})
    
    # DB
    if audit.get('db_env_has_secret') == 'clean':
        score += 10
        feedback.append("DB Env Clean (+10)")
    else:
        feedback.append("DB still has exposed password in Env")

    # Cache
    if audit.get('cache_cmd_has_secret') == 'clean':
        score += 10
        feedback.append("Redis Cmd Clean (+10)")
    else:
        feedback.append("Redis still has exposed password in Command")

    # API Env (Grouped)
    api_clean = (
        audit.get('api_env_db_secret') == 'clean' and
        audit.get('api_env_redis_secret') == 'clean' and
        audit.get('api_env_stripe_secret') == 'clean'
    )
    if api_clean:
        score += 15
        feedback.append("API Env Clean (+15)")
    else:
        feedback.append("API still has secrets in Env")

    # API Dockerfile
    if audit.get('api_env_flask_secret') == 'clean':
        score += 5
        feedback.append("API Dockerfile Clean (+5)")
    else:
        feedback.append("API Dockerfile still has FLASK_SECRET")

    # 2. Check Configuration (20 pts)
    config = result.get('configuration', {})
    
    if config.get('secrets_dir_exists') and config.get('secret_file_count', 0) >= 4:
        score += 10
        feedback.append("Secrets directory populated (+10)")
    else:
        feedback.append("Secrets directory missing or incomplete")

    if config.get('compose_defines_secrets'):
        score += 10
        feedback.append("Docker Compose defines secrets (+10)")
    else:
        feedback.append("Docker Compose missing top-level secrets definition")

    # 3. Check Functionality (30 pts)
    containers = result.get('containers', {})
    running_count = sum(1 for status in containers.values() if 'Up' in str(status) or 'running' in str(status))
    
    if running_count >= 4:
        score += 15
        feedback.append("All services running (+15)")
    elif running_count > 0:
        score += 5
        feedback.append(f"Partial services running: {running_count}/4 (+5)")
    else:
        feedback.append("No services running")

    func = result.get('functionality', {})
    if str(func.get('api_http_code')) == "200" and func.get('valid_json_response'):
        score += 15
        feedback.append("API Functional (+15)")
    else:
        feedback.append(f"API Check Failed (Code: {func.get('api_http_code')})")

    # 4. Check Report (10 pts)
    rep = result.get('report', {})
    if rep.get('exists') and rep.get('size_bytes', 0) > 50:
        score += 10
        feedback.append("Report exists (+10)")
    else:
        feedback.append("Report missing or empty")

    passed = score >= 60
    
    return {
        "passed": passed,
        "score": score,
        "feedback": "; ".join(feedback),
        "details": result
    }