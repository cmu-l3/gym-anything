#!/usr/bin/env python3
import json
import base64
import re
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_docker_systemd_conversion(traj, env_info, task_info):
    """
    Verifies the conversion of Docker containers to systemd services.
    """
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
        return {"passed": False, "score": 0, "feedback": f"Failed to load result: {str(e)}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback = []
    task_start = result.get('task_start', 0)

    services = result.get('services', {})
    db = services.get('db', {})
    api = services.get('api', {})
    frontend = services.get('frontend', {})
    
    # --- Criterion 1: Unit Files Existence & Creation (36 pts) ---
    # 12 pts each for existence + valid timestamp
    for name, svc in [("DB", db), ("API", api), ("Frontend", frontend)]:
        if svc.get('exists'):
            # Check modification time to ensure it was created during task (anti-gaming)
            if svc.get('mtime', 0) > task_start:
                score += 12
                feedback.append(f"✓ {name} unit file created.")
            else:
                # If file exists but old (shouldn't happen in clean env), partial points
                score += 5
                feedback.append(f"⚠ {name} unit file exists but has old timestamp.")
        else:
            feedback.append(f"✗ {name} unit file missing.")

    # --- Criterion 2: Dependencies (16 pts) ---
    # Parse base64 content
    def get_content(svc):
        try:
            return base64.b64decode(svc.get('content_b64', '')).decode('utf-8')
        except:
            return ""

    api_content = get_content(api)
    front_content = get_content(frontend)
    db_content = get_content(db)

    # API needs DB
    if re.search(r'(After|Requires)=.*acme-db\.service', api_content):
        score += 8
        feedback.append("✓ API depends on DB.")
    else:
        feedback.append("✗ API missing dependency on DB.")

    # Frontend needs API
    if re.search(r'(After|Requires)=.*acme-api\.service', front_content):
        score += 8
        feedback.append("✓ Frontend depends on API.")
    else:
        feedback.append("✗ Frontend missing dependency on API.")
    
    # --- Criterion 3: Docker dependency (5 pts) ---
    # Just checking one is enough to assume general knowledge
    if "docker.service" in db_content or "docker.service" in api_content:
        score += 5
        feedback.append("✓ Docker service dependency declared.")

    # --- Criterion 4: Systemd Status (25 pts) ---
    # Enabled (10 pts total)
    enabled_count = sum(1 for s in [db, api, frontend] if s.get('enabled'))
    if enabled_count == 3:
        score += 10
        feedback.append("✓ All services enabled.")
    elif enabled_count > 0:
        score += 5
        feedback.append(f"⚠ Only {enabled_count}/3 services enabled.")
    else:
        feedback.append("✗ No services enabled.")

    # Active (15 pts total)
    active_count = sum(1 for s in [db, api, frontend] if s.get('active'))
    if active_count == 3:
        score += 15
        feedback.append("✓ All services active.")
    elif active_count > 0:
        score += 7
        feedback.append(f"⚠ Only {active_count}/3 services active.")
    else:
        feedback.append("✗ No services active.")

    # --- Criterion 5: Restart Policy (5 pts) ---
    # Check for Restart=on-failure or always in at least one file
    if "Restart=" in db_content or "Restart=" in api_content:
        score += 5
        feedback.append("✓ Restart policy configured.")

    # --- Criterion 6: Functional Health (13 pts) ---
    functional = result.get('functional', {})
    if functional.get('db_connected'):
        score += 5
        feedback.append("✓ DB connection healthy.")
    else:
        feedback.append("✗ DB connection failed.")

    if functional.get('frontend_accessible'):
        score += 8
        feedback.append("✓ Frontend accessible via HTTP.")
    else:
        feedback.append("✗ Frontend not responding.")

    # Pass/Fail
    passed = score >= task_info['metadata']['pass_threshold']
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }