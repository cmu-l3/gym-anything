#!/usr/bin/env python3
import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_reverse_engineering(traj, env_info, task_info):
    """
    Verifies the Docker Compose Reverse Engineering task.
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
        return {"passed": False, "score": 0, "feedback": f"Failed to load result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback = []

    # 1. Compose File (20 pts)
    if result.get("compose_file_exists") and result.get("valid_yaml"):
        score += 20
        feedback.append("Valid docker-compose.yml created (+20)")
    elif result.get("compose_file_exists"):
        score += 10
        feedback.append("docker-compose.yml created but invalid YAML (+10)")
    else:
        feedback.append("No docker-compose.yml found (0/20)")

    # 2. Cleanup (10 pts)
    if result.get("originals_stopped"):
        score += 10
        feedback.append("Original containers stopped (+10)")
    else:
        feedback.append("Original containers still running (0/10)")

    # 3. New Deployment Running (10 pts)
    # We check if 4 containers were found running
    running_count = sum([
        1 if result.get(k) else 0 
        for k in ["db_container_found", "cache_container_found", "api_container_found", "web_container_found"]
    ])
    if running_count == 4:
        score += 10
        feedback.append("All 4 services running (+10)")
    else:
        score += int(running_count * 2.5)
        feedback.append(f"Only {running_count}/4 services running")
    
    # Check if they used compose
    if result.get("is_compose_project"):
        score += 5
        feedback.append("Deployed via Docker Compose (+5)")

    # 4. Functionality (20 pts)
    if str(result.get("api_items_status")) == "200":
        score += 10
        feedback.append("API /items endpoint working (+10)")
    
    if str(result.get("api_status_status")) == "200":
        score += 10
        feedback.append("API /status endpoint working (+10)")

    # 5. Configuration Fidelity (35 pts)
    
    # DB Volume Persistence
    db_mounts_str = result.get("db_mounts_json", "[]")
    if "inv-pgdata" in db_mounts_str:
        score += 5
        feedback.append("DB volume persisted (+5)")
    else:
        feedback.append("DB volume missing/incorrect")

    # Redis Command
    cache_cmd_str = result.get("cache_cmd_json", "[]")
    if "maxmemory 64mb" in cache_cmd_str and "allkeys-lru" in cache_cmd_str:
        score += 10
        feedback.append("Redis custom command captured (+10)")
    else:
        feedback.append("Redis custom command missing")

    # API Dual Networks
    api_nets_str = result.get("api_networks_json", "{}")
    if "inv-backend" in api_nets_str and "inv-frontend" in api_nets_str:
        score += 10
        feedback.append("API attached to both networks (+10)")
    else:
        feedback.append("API network configuration incomplete")

    # API Env Vars
    api_env_str = result.get("api_env_json", "[]")
    if "POSTGRES" in api_env_str or "DATABASE_URL" in api_env_str:
        # We look for the presence of the DB connection string parts
        if "postgresql://" in api_env_str and "inv-db" in api_env_str:
            score += 5
            feedback.append("API Env Vars correct (+5)")
    
    # Web Port
    web_ports_str = result.get("web_ports_json", "{}")
    if "8080" in web_ports_str:
        score += 5
        feedback.append("Web port 8080 mapped (+5)")

    # Final tally
    passed = score >= task_info["metadata"]["pass_threshold"]
    
    return {
        "passed": passed,
        "score": score,
        "feedback": "; ".join(feedback),
        "details": result
    }