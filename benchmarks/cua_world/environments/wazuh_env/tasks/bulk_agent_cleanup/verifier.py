#!/usr/bin/env python3
"""
Verifier for bulk_agent_cleanup task.

Criteria:
1. No agents matching 'temp-test-*' exist (50 pts)
2. 'production-web' and 'production-db' exist (40 pts)
3. 'wazuh-manager' (agent 000) exists (10 pts)
4. Total count checks out (implicit in above, but good for sanity)
"""

import json
import logging
import os
import tempfile
import re

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_bulk_agent_cleanup(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load result from container
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

    inventory = result.get('inventory', {})
    if not inventory.get('api_success'):
        return {"passed": False, "score": 0, "feedback": "Failed to query Wazuh API for verification"}

    agent_names = inventory.get('agent_names', [])
    
    score = 0
    feedback = []
    
    # 1. Check for stale agents (Should be 0)
    stale_pattern = re.compile(r'^temp-test-.*')
    stale_agents = [name for name in agent_names if stale_pattern.match(name)]
    
    if len(stale_agents) == 0:
        score += 50
        feedback.append("SUCCESS: All stale 'temp-test' agents removed.")
    else:
        feedback.append(f"FAIL: {len(stale_agents)} stale agents remain (e.g., {stale_agents[:3]}).")

    # 2. Check for production agents (Must exist)
    prod_web = "production-web" in agent_names
    prod_db = "production-db" in agent_names
    
    if prod_web and prod_db:
        score += 40
        feedback.append("SUCCESS: Production agents preserved.")
    else:
        missing = []
        if not prod_web: missing.append("production-web")
        if not prod_db: missing.append("production-db")
        feedback.append(f"FAIL: Critical production agents missing: {', '.join(missing)}.")

    # 3. Check for manager (Must exist)
    # Manager usually has name 'wazuh-manager' or ID '000'. 
    # API wrapper usually returns names. Manager is typically named hostname (wazuh.manager) or similar.
    # In setup we didn't rename it, so it's likely 'wazuh.manager' or 'wazuh-manager'.
    # We check if ANY agent is ID 000 (inventory ids) or generic manager check.
    # The export script exports IDs too.
    agent_ids = inventory.get('agent_ids', [])
    manager_exists = '000' in agent_ids
    
    if manager_exists:
        score += 10
        feedback.append("SUCCESS: Wazuh manager (Agent 000) preserved.")
    else:
        feedback.append("FAIL: Wazuh manager (Agent 000) was deleted!")

    return {
        "passed": score >= 100,
        "score": score,
        "feedback": " ".join(feedback)
    }