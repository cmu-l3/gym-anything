#!/usr/bin/env python3
"""
Verifier for docker_disaster_recovery task.
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_docker_disaster_recovery(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/dr_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback = []

    # Criteria 1: Data Integrity (45 pts)
    # Postgres
    cust_count = int(result.get('customer_count', 0))
    film_count = int(result.get('film_count', 0))
    rental_count = int(result.get('rental_count', 0))
    
    # Tolerances (in case of minor sequence id changes, though restore should be exact)
    if cust_count == 599:
        score += 15
        feedback.append("PostgreSQL Customer data restored exactly (15/15)")
    elif cust_count > 0:
        score += 5
        feedback.append(f"PostgreSQL Customer data partial: {cust_count} rows (5/15)")
    else:
        feedback.append("PostgreSQL Customer table empty/missing (0/15)")

    if film_count == 1000:
        score += 10
        feedback.append("PostgreSQL Film data restored exactly (10/10)")
    elif film_count > 0:
        score += 3
        feedback.append(f"PostgreSQL Film data partial (3/10)")

    if rental_count == 16044:
        score += 10
        feedback.append("PostgreSQL Rental data restored exactly (10/10)")
    elif rental_count > 0:
        score += 3
        feedback.append(f"PostgreSQL Rental data partial (3/10)")

    # Redis
    redis_keys = int(result.get('redis_key_count', 0))
    if redis_keys >= 48: # Allow losing 1-2 keys if flush/save timing was tight
        score += 10
        feedback.append(f"Redis session data restored ({redis_keys} keys) (10/10)")
    elif redis_keys > 0:
        score += 5
        feedback.append(f"Redis session data partial ({redis_keys} keys) (5/10)")
    else:
        feedback.append("Redis data missing (0/10)")

    # Criteria 2: Stack Functionality (10 pts)
    if result.get('web_response_code') == "200":
        score += 10
        feedback.append("Web/Nginx responding HTTP 200 (10/10)")
    else:
        feedback.append("Web/Nginx not healthy (0/10)")

    # Criteria 3: Anti-Gaming / Destruction Verification (10 pts)
    # The volumes MUST have been recreated after task start
    if result.get('volumes_destroyed_recreated', False):
        score += 10
        feedback.append("Verified: Volumes were destroyed and recreated (10/10)")
    else:
        feedback.append("FAILED: Volumes have timestamps from before task start. You must destroy the volumes to simulate disaster! (0/10)")

    # Criteria 4: Backup Artifacts (20 pts)
    if result.get('backup_sql_exists', False): score += 10
    else: feedback.append("Missing backup SQL file (0/10)")
    
    if result.get('backup_rdb_exists', False): score += 5
    else: feedback.append("Missing backup Redis RDB file (0/5)")
    
    if result.get('backup_compose_exists', False): score += 5
    else: feedback.append("Missing backup docker-compose.yml (0/5)")

    # Criteria 5: Runbook (15 pts)
    runbook_exists = result.get('runbook_exists', False)
    runbook_len = result.get('runbook_length', 0)
    content = result.get('runbook_content', "").lower()
    
    if runbook_exists and runbook_len > 100:
        s = 5
        if "restore" in content: s += 5
        if "backup" in content: s += 5
        score += s
        feedback.append(f"Runbook verification passed ({s}/15)")
    else:
        feedback.append("Runbook missing or too short (0/15)")

    # Pass Threshold
    passed = (score >= 65) and result.get('volumes_destroyed_recreated', False)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }