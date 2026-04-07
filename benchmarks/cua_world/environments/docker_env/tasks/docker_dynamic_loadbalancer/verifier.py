#!/usr/bin/env python3
"""
Verifier for docker_dynamic_loadbalancer task.

Scoring (100 points):
- Script functionality (runs without error): 30 pts
- Dynamic Discovery (found the new probe container): 25 pts
- Config Validity (nginx -t passed): 15 pts
- Nginx Reload/Traffic (curl returned 200): 20 pts
- Label Filtering (ignored non-backend container): 10 pts

Pass threshold: 70 points
"""

import json
import tempfile
import os
import logging

logger = logging.getLogger(__name__)

def verify_dynamic_loadbalancer(traj, env_info, task_info):
    copy_from_env = env_info.get("copy_from_env")
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env unavailable"}

    # Retrieve result file
    try:
        temp_file = tempfile.NamedTemporaryFile(delete=False, suffix=".json")
        temp_path = temp_file.name
        temp_file.close()

        try:
            copy_from_env("/tmp/lb_result.json", temp_path)
            with open(temp_path, "r") as f:
                result = json.load(f)
        finally:
            if os.path.exists(temp_path):
                os.unlink(temp_path)
    except FileNotFoundError:
        return {"passed": False, "score": 0, "feedback": "Result file not found in environment."}
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Error reading result: {e}"}

    score = 0
    feedback_parts = []

    # Criterion 1: Script runs (30 pts)
    if result.get("script_runs_successfully", 0):
        score += 30
        feedback_parts.append("Script runs successfully (+30)")
    elif result.get("script_exists", 0):
        score += 10
        feedback_parts.append("Script exists but crashed during execution (10/30)")
    else:
        feedback_parts.append("Script not found (0/30)")

    # Criterion 2: Dynamic Discovery (25 pts)
    if result.get("probe_detected", 0):
        score += 25
        feedback_parts.append("Dynamic discovery verified: Found new container (+25)")
    else:
        feedback_parts.append("Dynamic discovery failed: Did not add new container IP to config (0/25)")

    # Criterion 3: Config Validity (15 pts)
    if result.get("nginx_config_valid", 0):
        score += 15
        feedback_parts.append("Generated Nginx config is valid (+15)")
    else:
        feedback_parts.append("Generated Nginx config is invalid (0/15)")

    # Criterion 4: Traffic Flowing (20 pts)
    if result.get("traffic_flowing", 0):
        score += 20
        feedback_parts.append("Traffic flowing: Nginx reloaded and routing requests (+20)")
    else:
        feedback_parts.append("Traffic failed: Nginx returning errors or not reachable (0/20)")

    # Criterion 5: Label Filtering (10 pts)
    if result.get("label_filtering_verified", 0):
        score += 10
        feedback_parts.append("Label filtering verified: Ignored non-backend containers (+10)")
    else:
        # If script failed to run, we can't give points here either usually, 
        # but if it ran and included the noise IP, this is 0.
        if result.get("script_runs_successfully", 0):
            feedback_parts.append("Label filtering failed: Included non-backend containers (0/10)")
        else:
            feedback_parts.append("Label filtering not tested (script failed) (0/10)")

    passed = score >= 70
    
    return {
        "passed": passed,
        "score": score,
        "feedback": "; ".join(feedback_parts)
    }