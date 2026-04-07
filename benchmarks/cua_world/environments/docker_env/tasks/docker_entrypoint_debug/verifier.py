#!/usr/bin/env python3
"""
Verifier for docker_entrypoint_debug@1
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_docker_entrypoint_debug(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Read result file
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
    
    services = result.get('services', {})
    
    # Evaluate each service (20 points each: 10 for running/healthy + 10 for proper rebuild)
    # Re-tuned based on task design: 
    #   Service 1, 2: 15 pts
    #   Service 3, 4: 20 pts
    #   Rebuilds: 10 pts global
    #   Cleanup: 5 pts
    #   Report: 15 pts
    
    # Helper to check service
    def check_service(name):
        s = services.get(name, {})
        running = s.get('running', 0) == 1
        uptime = s.get('uptime', 0)
        restarts = s.get('restarts', 0)
        healthy = s.get('health') == 'healthy'
        rebuilt = s.get('rebuilt', False)
        
        # Stable means running > 5s and not restart looping (restarts < 3 for this session)
        stable = running and uptime > 5 and restarts < 5
        return stable, healthy, rebuilt

    # 1. acme-cache-warmer (15 pts)
    s1_stable, s1_healthy, s1_rebuilt = check_service('acme-cache-warmer')
    if s1_stable and s1_healthy:
        score += 15
        feedback.append("acme-cache-warmer: Running & Healthy (+15)")
    elif s1_stable:
        score += 10
        feedback.append("acme-cache-warmer: Running but log check failed (+10)")
    else:
        feedback.append("acme-cache-warmer: Not running/stable")

    # 2. acme-event-processor (15 pts)
    s2_stable, s2_healthy, s2_rebuilt = check_service('acme-event-processor')
    if s2_stable and s2_healthy:
        score += 15
        feedback.append("acme-event-processor: Running & Healthy (+15)")
    elif s2_stable:
        score += 10
        feedback.append("acme-event-processor: Running but log check failed (+10)")
    else:
        feedback.append("acme-event-processor: Not running/stable")

    # 3. acme-report-generator (20 pts)
    s3_stable, s3_healthy, s3_rebuilt = check_service('acme-report-generator')
    if s3_stable and s3_healthy:
        score += 20
        feedback.append("acme-report-generator: Running & Responding (+20)")
    elif s3_stable:
        score += 10
        feedback.append("acme-report-generator: Running but health check failed (+10)")
    else:
        feedback.append("acme-report-generator: Not running/stable")

    # 4. acme-static-server (20 pts)
    s4_stable, s4_healthy, s4_rebuilt = check_service('acme-static-server')
    if s4_stable and s4_healthy:
        score += 20
        feedback.append("acme-static-server: Running & Responding (+20)")
    elif s4_stable:
        score += 10
        feedback.append("acme-static-server: Running but health check failed (+10)")
    else:
        feedback.append("acme-static-server: Not running/stable")

    # 5. Rebuild verification (10 pts)
    # Requires all images to have been rebuilt
    rebuilt_count = sum([s1_rebuilt, s2_rebuilt, s3_rebuilt, s4_rebuilt])
    if rebuilt_count == 4:
        score += 10
        feedback.append("All images rebuilt (+10)")
    elif rebuilt_count > 0:
        score += 5
        feedback.append(f"Some images rebuilt ({rebuilt_count}/4) (+5)")
    else:
        feedback.append("Images NOT rebuilt (using overrides?)")

    # 6. Report (15 pts)
    rep = result.get('report', {})
    if rep.get('exists') and rep.get('size', 0) > 50:
        score += 15
        feedback.append("Report exists (+15)")
    else:
        feedback.append("Report missing/empty")

    # 7. Cleanup (5 pts)
    # Implicitly checked if named containers are stable.
    # We'll give these points if all 4 services are stable, assuming the bad ones are gone/replaced.
    if s1_stable and s2_stable and s3_stable and s4_stable:
        score += 5
        feedback.append("Cleanup/Stability (+5)")

    pass_threshold = task_info.get('metadata', {}).get('pass_threshold', 60)
    passed = score >= pass_threshold
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }