#!/usr/bin/env python3
"""
Verifier for docker_incident_rca task.

Scoring (100 points):
- Service Restoration (50 pts total):
    - DB Running: 15
    - API Running: 15
    - Worker Running: 10
    - Web Running: 10
- Root Cause Fix (15 pts):
    - PostgreSQL max_connections >= 20
- Functional Verification (10 pts):
    - API Health Check returns 200
- Incident Report (25 pts):
    - Exists & Created during task: 10
    - Correct content (root cause & timeline keywords): 15

Pass threshold: 60 points
"""

import json
import tempfile
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_docker_incident_rca(traj, env_info, task_info):
    """Verify the incident resolution and report."""
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load result JSON
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/rca_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback = []
    task_start = result.get('task_start', 0)

    # 1. Service Restoration (50 pts)
    services = {
        'db': ('db_running', 15),
        'api': ('api_running', 15),
        'worker': ('worker_running', 10),
        'web': ('web_running', 10)
    }

    running_count = 0
    for name, (key, points) in services.items():
        if result.get(key) is True:
            score += points
            running_count += 1
            feedback.append(f"{name.upper()} running (+{points})")
        else:
            feedback.append(f"{name.upper()} NOT running")

    # 2. Root Cause Fix (15 pts)
    try:
        max_conns = int(result.get('db_max_connections', 0))
    except (ValueError, TypeError):
        max_conns = 0
    
    if max_conns >= 20:
        score += 15
        feedback.append(f"Root cause fixed: max_connections={max_conns} (+15)")
    elif max_conns > 5:
        score += 5
        feedback.append(f"Partial fix: max_connections={max_conns} (low) (+5)")
    else:
        feedback.append(f"Root cause NOT fixed: max_connections={max_conns} (still too low)")

    # 3. Functional Check (10 pts)
    http_status = str(result.get('api_http_status', '000'))
    if http_status == '200':
        score += 10
        feedback.append("API responding HTTP 200 (+10)")
    else:
        feedback.append(f"API failing: HTTP {http_status}")

    # 4. Incident Report (25 pts)
    report_exists = result.get('report_exists', False)
    report_mtime = int(result.get('report_mtime', 0))
    report_content = result.get('report_content_preview', '').lower()

    if report_exists and report_mtime > task_start:
        score += 10
        feedback.append("Incident report created (+10)")
        
        # Content Analysis
        keywords_cause = ['connection', 'max_connections', 'pool', 'exhaustion', 'limit']
        keywords_timeline = ['cascade', 'fail', 'crash', 'log', 'order']
        
        has_cause = any(k in report_content for k in keywords_cause)
        has_timeline = any(k in report_content for k in keywords_timeline)
        
        if has_cause:
            score += 10
            feedback.append("Report identifies root cause (+10)")
        if has_timeline:
            score += 5
            feedback.append("Report includes timeline (+5)")
    else:
        feedback.append("No valid incident report found")

    # 5. VLM Verification (Bonus/Validation check)
    # We rely primarily on programmatic checks here, but VLM could verify 
    # the terminal activity if we implemented it. For now, programmatic is robust enough.

    passed = score >= 60 and running_count == 4 and max_conns >= 20
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback),
        "details": result
    }