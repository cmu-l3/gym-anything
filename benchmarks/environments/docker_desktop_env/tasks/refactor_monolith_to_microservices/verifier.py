#!/usr/bin/env python3
"""
Verifier for refactor_monolith_to_microservices task.
"""

import json
import tempfile
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_refactor_monolith(traj, env_info, task_info):
    """
    Verify the monolithic app was refactored into microservices.
    
    Criteria:
    1. Architecture (30 pts): Two distinct containers (app and db) running via compose.
    2. Database Image (20 pts): DB service uses official postgres image.
    3. App Image Cleaned (20 pts): App Dockerfile no longer installs postgres server.
    4. Connectivity (20 pts): App reachable and talking to DB.
    5. Persistence (10 pts): Database uses named volume.
    """
    
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Retrieve result from container
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read verification data: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)
            
    score = 0
    feedback_parts = []
    
    # 1. Architecture Check (30 pts)
    # Require valid compose file and at least 2 services running
    compose_valid = result.get('compose_valid', False)
    service_count = result.get('service_count', 0)
    app_running = result.get('app_running', False)
    db_running = result.get('db_running', False)
    
    if compose_valid and service_count >= 2 and app_running and db_running:
        score += 30
        feedback_parts.append("Microservices architecture active (+30)")
    elif compose_valid and service_count >= 2:
        score += 20
        feedback_parts.append("Microservices running but specific services not identified (+20)")
    else:
        feedback_parts.append(f"Architecture check failed: {service_count} services running")
        
    # 2. Database Image (20 pts)
    if result.get('db_image_correct', False):
        score += 20
        feedback_parts.append("Official Postgres image used (+20)")
    else:
        feedback_parts.append("Incorrect DB image")

    # 3. App Image Cleaned (20 pts)
    # The agent should have removed the 'apt-get install postgresql' bloat
    if result.get('app_image_clean', False):
        score += 20
        feedback_parts.append("App Dockerfile optimized/cleaned (+20)")
    else:
        feedback_parts.append("App Dockerfile still contains legacy Postgres installation")

    # 4. Connectivity & Functionality (20 pts)
    # We check if the app is responding HTTP 200.
    # The app code itself checks DB connection and returns status.
    if result.get('app_accessible', False):
        score += 20
        feedback_parts.append("App accessible and healthy (+20)")
        
        # Bonus check on response content if needed
        response_str = result.get('app_response', '')
        if '"service": "notes-app"' not in response_str:
            feedback_parts.append("(Warning: Unexpected app response content)")
    else:
        feedback_parts.append("App not accessible on localhost:5000")

    # 5. Persistence (10 pts)
    if result.get('volume_used', False):
        score += 10
        feedback_parts.append("Database persistence configured (+10)")
    else:
        feedback_parts.append("No database volume detected")

    # Final Score
    passed = score >= 70
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }