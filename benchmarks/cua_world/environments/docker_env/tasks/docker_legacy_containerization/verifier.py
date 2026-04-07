#!/usr/bin/env python3
import json
import os
import tempfile
import logging

logger = logging.getLogger(__name__)

def verify_docker_legacy_containerization(traj, env_info, task_info):
    """
    Verifies that the legacy application was successfully containerized.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Retrieve result file from container
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve or parse result: {str(e)}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback = []

    # Criterion 1: Files Exist (20 pts)
    if result.get('has_dockerfile', False):
        score += 10
        feedback.append("Dockerfile created (+10)")
    else:
        feedback.append("Missing Dockerfile")

    if result.get('has_compose', False):
        score += 10
        feedback.append("docker-compose.yml created (+10)")
    else:
        feedback.append("Missing docker-compose.yml")

    # Criterion 2: Containers Running (25 pts)
    # We want at least 3 containers, specifically identifying DB, API, Nginx
    containers_ok = 0
    if result.get('has_db_container', False): containers_ok += 1
    if result.get('has_api_container', False): containers_ok += 1
    if result.get('has_nginx_container', False): containers_ok += 1
    
    # Scale points: 1=5, 2=15, 3=25
    if containers_ok >= 3:
        score += 25
        feedback.append("All services running (+25)")
    elif containers_ok == 2:
        score += 15
        feedback.append("Two services running (+15)")
    elif containers_ok == 1:
        score += 5
        feedback.append("One service running (+5)")
    else:
        feedback.append("No correct services detected running")

    # Criterion 3: Endpoints Reachable (30 pts)
    if result.get('root_endpoint_ok', False):
        score += 10
        feedback.append("Root URL (Nginx) serving HTML (+10)")
    else:
        feedback.append("Root URL not serving expected HTML")

    if result.get('api_endpoint_ok', False):
        score += 20
        feedback.append("API endpoint returning JSON (+20)")
    else:
        feedback.append("API endpoint not returning valid JSON")

    # Criterion 4: Data Integrity (25 pts)
    data_points = 0
    
    # Content check via API
    if result.get('content_correct', False):
        data_points += 10
        feedback.append("API returns correct seed data (+10)")
    
    # DB row count check (should be 50)
    try:
        count = int(result.get('db_row_count', 0))
        if count == 50:
            data_points += 15
            feedback.append("Database initialized with 50 rows (+15)")
        elif count > 0:
            data_points += 5
            feedback.append(f"Database has rows ({count}) but not 50 (+5)")
        else:
            feedback.append("Database empty or not accessible")
    except:
        feedback.append("Could not verify database content")
    
    score += data_points

    # Final Verification
    passed = score >= 60 and result.get('api_endpoint_ok', False)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": "; ".join(feedback)
    }