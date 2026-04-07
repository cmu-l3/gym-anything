#!/usr/bin/env python3
"""
Verifier for docker_hybrid_network_debug task.

Scoring (100 points):
- Backend Config (Host Access): 35 points
  - Uses host-gateway/extra_hosts: 20 pts
  - Env var points to host.docker.internal: 15 pts
- Frontend Config (Service Discovery): 25 points
  - Env var points to shop-backend: 25 pts
- Frontend Config (Port Mapping): 25 points
  - Maps 8080 -> 3000: 25 pts
- Functional Success: 15 points
  - End-to-end curl works: 15 pts

Pass Threshold: 75 points
"""

import json
import tempfile
import os
import logging

logger = logging.getLogger(__name__)

def verify_docker_hybrid_network_debug(traj, env_info, task_info):
    copy_from_env = env_info.get("copy_from_env")
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env unavailable"}

    try:
        temp_file = tempfile.NamedTemporaryFile(delete=False, suffix=".json")
        temp_path = temp_file.name
        temp_file.close()
        
        try:
            copy_from_env("/tmp/hybrid_network_result.json", temp_path)
            with open(temp_path, "r") as f:
                result = json.load(f)
        finally:
            try:
                os.unlink(temp_path)
            except Exception:
                pass
                
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Error reading result: {e}"}

    score = 0
    feedback_parts = []

    # 1. Backend -> Host Connectivity (35 pts)
    # Using extra_hosts: "host.docker.internal:host-gateway" is the standard docker-compose way
    if result.get("backend_extra_hosts", False):
        score += 20
        feedback_parts.append("Backend: 'extra_hosts' configured (+20)")
    else:
        feedback_parts.append("Backend: 'extra_hosts' missing (0/20)")

    if result.get("backend_inventory_url_fixed", False):
        score += 15
        feedback_parts.append("Backend: INVENTORY_URL fixed (+15)")
    else:
        feedback_parts.append("Backend: INVENTORY_URL incorrect (0/15)")

    # 2. Frontend -> Backend Service Discovery (25 pts)
    if result.get("frontend_api_url_fixed", False):
        score += 25
        feedback_parts.append("Frontend: API_URL hostname fixed (+25)")
    else:
        feedback_parts.append("Frontend: API_URL points to wrong service (0/25)")

    # 3. Frontend Port Mapping (25 pts)
    if result.get("frontend_port_map_fixed", False):
        score += 25
        feedback_parts.append("Frontend: Port mapping fixed 8080->3000 (+25)")
    else:
        feedback_parts.append("Frontend: Port mapping incorrect (0/25)")

    # 4. End-to-End Functionality (15 pts)
    # If the curl worked and returned the legacy data, it proves the whole chain is alive.
    if result.get("has_legacy_data", False):
        score += 15
        feedback_parts.append("End-to-end: Full connectivity verified (+15)")
    else:
        feedback_parts.append("End-to-end: Failed to retrieve legacy inventory data (0/15)")

    # Anti-gaming / Sanity check
    if not result.get("host_service_running", False):
        score = 0
        feedback_parts = ["CRITICAL: Legacy Inventory Service on host was stopped! It must remain running."]

    pass_threshold = task_info.get("metadata", {}).get("pass_threshold", 75)
    passed = score >= pass_threshold

    return {
        "passed": passed,
        "score": score,
        "feedback": "; ".join(feedback_parts)
    }