#!/usr/bin/env python3
"""
Verifier for docker_volume_recovery task.

Scoring (100 pts total):
1. Infrastructure (30 pts):
   - DB Running (10)
   - Redis Running (10)
   - App Running (10)
2. Data Restoration (35 pts):
   - Postgres Tracks correct (15)
   - Redis Keys restored (10)
   - API Verification (10)
3. Automation (35 pts):
   - Backup script exists & executable (10)
   - Script generates valid SQL backup (15)
   - Script generates Redis backup (10)

Pass Threshold: 60 pts
"""

import json
import tempfile
import os
import logging

logger = logging.getLogger(__name__)

def verify_docker_volume_recovery(traj, env_info, task_info):
    copy_from_env = env_info.get("copy_from_env")
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env unavailable"}

    # Load result
    try:
        temp_file = tempfile.NamedTemporaryFile(delete=False, suffix=".json")
        temp_path = temp_file.name
        temp_file.close()
        copy_from_env("/tmp/volume_recovery_result.json", temp_path)
        with open(temp_path, "r") as f:
            result = json.load(f)
        os.unlink(temp_path)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result: {e}"}

    score = 0
    feedback = []

    # 1. Infrastructure (30 pts)
    containers = result.get("containers", {})
    if containers.get("db", 0) > 0:
        score += 10
        feedback.append("PostgreSQL running (+10)")
    else:
        feedback.append("PostgreSQL NOT running")

    if containers.get("redis", 0) > 0:
        score += 10
        feedback.append("Redis running (+10)")
    else:
        feedback.append("Redis NOT running")

    if containers.get("app", 0) > 0:
        score += 10
        feedback.append("Flask App running (+10)")
    else:
        feedback.append("Flask App NOT running")

    # 2. Data Restoration (35 pts)
    # Postgres
    try:
        tracks = int(result.get("postgres", {}).get("tracks", 0))
    except ValueError:
        tracks = 0
    
    # Expected: 3503 tracks
    if tracks == 3503:
        score += 15
        feedback.append("PostgreSQL data verified (3503 tracks) (+15)")
    elif tracks > 0:
        score += 5
        feedback.append(f"PostgreSQL data partial ({tracks} tracks, expected 3503) (+5)")
    else:
        feedback.append("PostgreSQL empty or restore failed")

    # Redis
    try:
        keys = int(result.get("redis", {}).get("keys", 0))
    except ValueError:
        keys = 0
    
    # Expected >= 50
    if keys >= 50:
        score += 10
        feedback.append(f"Redis data verified ({keys} keys) (+10)")
    elif keys > 0:
        score += 5
        feedback.append(f"Redis data partial ({keys} keys) (+5)")
    else:
        feedback.append("Redis empty or restore failed")

    # API End-to-End
    api = result.get("api", {})
    if api.get("status") == 200:
        resp = api.get("response", {})
        if resp.get("tracks") == 3503 and resp.get("sessions", 0) >= 50:
            score += 10
            feedback.append("API health check passed (+10)")
        else:
            feedback.append("API reachable but returned incorrect data")
    else:
        feedback.append("API not reachable")

    # 3. Automation (35 pts)
    backup = result.get("backup_script", {})
    if backup.get("exists") and backup.get("executable"):
        score += 10
        feedback.append("Backup script created and executable (+10)")
        
        if backup.get("generated_sql"):
            score += 15
            feedback.append("Backup script produced valid SQL (+15)")
        else:
            feedback.append("Backup script failed to produce SQL")
            
        if backup.get("generated_redis"):
            score += 10
            feedback.append("Backup script produced Redis export (+10)")
        else:
            feedback.append("Backup script failed to produce Redis export")
    else:
        feedback.append("Backup script missing or not executable")

    passed = score >= 60
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }