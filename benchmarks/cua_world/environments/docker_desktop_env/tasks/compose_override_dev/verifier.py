#!/usr/bin/env python3
"""
Verifier for compose_override_dev@1 task.
Scores based on container inspection and file system checks.
"""

import json
import tempfile
import os
import logging

logger = logging.getLogger(__name__)

def verify_compose_override_dev(traj, env_info, task_info):
    """
    Verify the Docker Compose override task.
    
    Rubric (100 pts):
    1. Override File Integrity (10 pts): Exists, Valid YAML, Base unmodified, Created during task.
    2. Service Health (25 pts): All 3 services running.
    3. API Configuration (45 pts):
       - FLASK_DEBUG=1 (10 pts)
       - FLASK_ENV=development (10 pts)
       - Bind mount ./api:/app (15 pts)
       - Command override (10 pts)
    4. Port Mappings (20 pts):
       - API Debug Port 5678 (10 pts)
       - DB Port 5432 (10 pts)
    """
    
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load result
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

    # 1. File Checks (10 pts)
    if result.get('override_exists') and result.get('valid_yaml'):
        if not result.get('base_modified'):
            if result.get('file_created_during_task'):
                score += 10
                feedback.append("Valid override file created.")
            else:
                score += 5
                feedback.append("Override file exists but timestamp check failed.")
        else:
            feedback.append("FAIL: Original docker-compose.yml was modified.")
            return {"passed": False, "score": 0, "feedback": "Original docker-compose.yml must not be modified."}
    else:
        feedback.append("Override file missing or invalid YAML.")

    # 2. Service Health (25 pts)
    services = result.get('services_running', {})
    if services.get('api') and services.get('db') and services.get('web'):
        score += 25
        feedback.append("All services running.")
    else:
        # Partial credit if some run? No, typically all need to run to verify config works.
        running = [k for k,v in services.items() if v]
        if running:
            score += 10
            feedback.append(f"Only {len(running)}/3 services running: {', '.join(running)}.")
        else:
            feedback.append("No services running.")

    # 3. API Config (45 pts)
    api_config = result.get('api_config', {})
    
    # Env vars
    env_vars = api_config.get('env', [])
    # Parse env list ["KEY=VAL", ...] into dict
    env_dict = {}
    for item in env_vars:
        if '=' in item:
            k, v = item.split('=', 1)
            env_dict[k] = v
            
    if env_dict.get('FLASK_DEBUG') == '1':
        score += 10
        feedback.append("FLASK_DEBUG set correctly.")
    else:
        feedback.append("FLASK_DEBUG missing or wrong.")

    if env_dict.get('FLASK_ENV') == 'development':
        score += 10
        feedback.append("FLASK_ENV set correctly.")
    else:
        feedback.append("FLASK_ENV missing or wrong.")

    # Bind Mount
    mounts = api_config.get('mounts', [])
    mount_found = False
    for m in mounts:
        # Check for bind mount to /app
        if m.get('Type') == 'bind' and m.get('Destination') == '/app':
            mount_found = True
            break
    if mount_found:
        score += 15
        feedback.append("API bind mount confirmed.")
    else:
        feedback.append("API bind mount missing.")

    # Command
    cmd = api_config.get('cmd', [])
    # cmd is a list like ["flask", "run", ...] or a shell string
    cmd_str = " ".join(cmd) if isinstance(cmd, list) else str(cmd)
    if 'flask run' in cmd_str and '--reload' in cmd_str:
        score += 10
        feedback.append("API command override correct.")
    else:
        feedback.append(f"API command incorrect: {cmd_str}")

    # 4. Port Mappings (20 pts)
    # API Ports
    api_ports = api_config.get('ports', {})
    # JSON structure: {"5678/tcp": [{"HostIp": "0.0.0.0", "HostPort": "5678"}], ...}
    
    if api_ports and "5678/tcp" in api_ports and api_ports["5678/tcp"]:
        score += 10
        feedback.append("API debug port 5678 mapped.")
    else:
        feedback.append("API debug port 5678 not mapped.")

    # DB Ports
    db_config = result.get('db_config', {})
    db_ports = db_config.get('ports', {})
    
    if db_ports and "5432/tcp" in db_ports and db_ports["5432/tcp"]:
        score += 10
        feedback.append("DB port 5432 mapped.")
    else:
        feedback.append("DB port 5432 not mapped.")

    passed = (score >= 70) and services.get('api') and services.get('db') and services.get('web')

    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }