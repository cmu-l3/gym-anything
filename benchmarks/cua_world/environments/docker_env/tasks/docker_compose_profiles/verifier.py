#!/usr/bin/env python3
"""
Verifier for docker_compose_profiles task.
Verifies that services are correctly assigned to Docker Compose profiles.
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_docker_compose_profiles(traj, env_info, task_info):
    """
    Verify the Docker Compose configuration and runtime behavior.
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
        return {"passed": False, "score": 0, "feedback": f"Failed to load result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback = []
    
    # Extract data
    config = result.get('compose_config', {})
    services = config.get('services', {})
    runtime = result.get('runtime_checks', {})
    
    metadata = task_info.get('metadata', {})
    core_services = set(metadata.get('core_services', []))
    profile_map = metadata.get('profile_map', {})

    if not services:
        return {"passed": False, "score": 0, "feedback": "docker-compose.yml is invalid or empty"}

    # CRITERION 1: Core services should NOT have a profile (or explicit default) - 30 pts
    core_score = 0
    for svc_name in core_services:
        svc_conf = services.get(svc_name)
        if not svc_conf:
            feedback.append(f"Missing core service: {svc_name}")
            continue
        
        profiles = svc_conf.get('profiles', [])
        # Valid if profiles is empty/None OR contains "default" (unlikely usage but valid spec)
        # Note: 'docker compose config' might normalize this. Usually empty for default.
        if not profiles:
            core_score += 10
        elif "default" in profiles: # Explicit default
             core_score += 10
        else:
            feedback.append(f"Core service '{svc_name}' should start by default but has profiles: {profiles}")
    
    score += core_score
    feedback.append(f"Core services config: {core_score}/30")

    # CRITERION 2: Profiled services configuration - 40 pts
    # (gui: 15, monitoring: 15, test/tools: 10)
    profile_score = 0
    
    def check_service_profile(name, expected_profile, points):
        svc_conf = services.get(name)
        if not svc_conf:
            return 0, f"Missing service {name}"
        
        profiles = svc_conf.get('profiles', [])
        if expected_profile in profiles:
            return points, ""
        else:
            return 0, f"Service '{name}' expected profile '{expected_profile}', found {profiles}"

    # Check GUI services
    gui_pts = 0
    p, msg = check_service_profile('db-admin', 'gui', 7.5)
    gui_pts += p; feedback.append(msg) if msg else None
    p, msg = check_service_profile('cache-admin', 'gui', 7.5)
    gui_pts += p; feedback.append(msg) if msg else None
    
    # Check Monitoring
    mon_pts = 0
    p, msg = check_service_profile('prometheus', 'monitoring', 7.5)
    mon_pts += p; feedback.append(msg) if msg else None
    p, msg = check_service_profile('grafana', 'monitoring', 7.5)
    mon_pts += p; feedback.append(msg) if msg else None

    # Check Test/Tools
    tool_pts = 0
    p, msg = check_service_profile('test-runner', 'test', 5)
    tool_pts += p; feedback.append(msg) if msg else None
    p, msg = check_service_profile('db-seeder', 'tools', 5)
    tool_pts += p; feedback.append(msg) if msg else None
    
    score += gui_pts + mon_pts + tool_pts
    feedback.append(f"Profile config: {gui_pts + mon_pts + tool_pts}/40")

    # CRITERION 3: Runtime Verification - 20 pts
    # Default up should run exactly 3 core services
    default_running = runtime.get('default_running_count', -1)
    if default_running == 3:
        score += 10
        feedback.append("Runtime Check 1: 'docker compose up' started 3 containers (+10)")
    else:
        feedback.append(f"Runtime Check 1 Failed: Expected 3 running containers, got {default_running}")

    # GUI profile up should run 5 services (3 core + 2 gui)
    # Note: If they depend on core, core starts too.
    gui_running = runtime.get('gui_running_count', -1)
    if gui_running == 5:
        score += 10
        feedback.append("Runtime Check 2: 'docker compose --profile gui up' started 5 containers (+10)")
    else:
        # Partial credit if at least the gui ones started (>=2)
        if gui_running >= 2:
             score += 5
             feedback.append(f"Runtime Check 2 Partial: Started {gui_running} containers (+5)")
        else:
             feedback.append(f"Runtime Check 2 Failed: Expected 5 running containers, got {gui_running}")

    # CRITERION 4: File Integrity - 10 pts
    if result.get('file_modified'):
        score += 10
        feedback.append("File modification detected (+10)")
    else:
        feedback.append("No changes detected in docker-compose.yml (0/10)")

    # Final tally
    passed = score >= 70
    
    return {
        "passed": passed,
        "score": score,
        "feedback": "; ".join([f for f in feedback if f])
    }