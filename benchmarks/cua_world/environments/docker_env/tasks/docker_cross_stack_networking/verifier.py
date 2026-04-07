#!/usr/bin/env python3
"""
Verifier for docker_cross_stack_networking task.

Scoring (100 points):
- Shared Docker network created and both containers attached: 35 pts
  - (20 for network creation, 15 for both attached)
- Storefront configuration updated correctly (no localhost): 15 pts
- Functional Test: Storefront returns product data: 25 pts
- Security/Best Practice: No 'network_mode: host': 10 pts
- Containers running and healthy: 15 pts

Pass threshold: 75 points
"""

import json
import tempfile
import os
import logging
import re

logger = logging.getLogger(__name__)

PASS_THRESHOLD = 75

def verify_cross_stack_networking(traj, env_info, task_info):
    """Verify networking configuration and functional connectivity."""
    copy_from_env = env_info.get("copy_from_env")
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env unavailable"}

    try:
        temp_file = tempfile.NamedTemporaryFile(delete=False, suffix=".json")
        temp_path = temp_file.name
        temp_file.close()

        try:
            copy_from_env("/tmp/networking_result.json", temp_path)
            with open(temp_path, "r") as f:
                result = json.load(f)
        finally:
            try:
                os.unlink(temp_path)
            except Exception:
                pass

    except FileNotFoundError:
        return {"passed": False, "score": 0, "feedback": "Result file not found"}
    except json.JSONDecodeError as e:
        return {"passed": False, "score": 0, "feedback": f"JSON malformed: {e}"}
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Error: {e}"}

    score = 0
    feedback_parts = []
    subscores = {}

    # 1. Network Configuration (35 pts)
    shared_exists = result.get("shared_network_exists", 0)
    common_net = result.get("common_network_name", "none")
    
    if shared_exists:
        score += 35
        subscores["network"] = True
        feedback_parts.append(f"Shared network configured ({common_net}) (+35)")
    else:
        subscores["network"] = False
        feedback_parts.append("Containers do not share a custom external network (0/35)")

    # 2. API Configuration (15 pts)
    api_correct = result.get("api_url_correct", 0)
    api_val = result.get("api_url_value", "unknown")
    
    if api_correct:
        score += 15
        subscores["config"] = True
        feedback_parts.append(f"Storefront config correct ({api_val}) (+15)")
    else:
        subscores["config"] = False
        feedback_parts.append(f"Storefront config incorrect or using localhost ({api_val}) (0/15)")

    # 3. Functional Test (25 pts)
    has_data = result.get("has_product_data", 0)
    
    if has_data:
        score += 25
        subscores["functional"] = True
        feedback_parts.append("Storefront returns correct product data (+25)")
    else:
        subscores["functional"] = False
        feedback_parts.append("Storefront failed to load product data (0/25)")

    # 4. Security/Constraint Check (10 pts)
    using_host = result.get("using_host_net", 0)
    
    if not using_host:
        score += 10
        subscores["security"] = True
        feedback_parts.append("Correct network isolation (no host mode) (+10)")
    else:
        subscores["security"] = False
        feedback_parts.append("Security Violation: Used 'network_mode: host' (0/10)")

    # 5. Operational Check (15 pts)
    inv_running = result.get("inventory_running", 0)
    store_running = result.get("storefront_running", 0)
    
    if inv_running and store_running:
        score += 15
        subscores["running"] = True
        feedback_parts.append("Both services running (+15)")
    else:
        subscores["running"] = False
        feedback_parts.append("One or more services not running (0/15)")

    passed = score >= PASS_THRESHOLD
    
    # Critical failure override: if functional test fails, it's hard to pass
    if not has_data and passed:
        # Edge case: If they got points elsewhere but main goal failed
        passed = False
        feedback_parts.append("FAILED: Connectivity not established despite config changes.")

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts),
        "details": subscores
    }