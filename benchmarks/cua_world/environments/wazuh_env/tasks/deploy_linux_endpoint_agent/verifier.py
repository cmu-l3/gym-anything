#!/usr/bin/env python3
"""
Verifier for deploy_linux_endpoint_agent task.
Verifies that the Wazuh agent is installed, running, and successfully connected to the manager.
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_deploy_linux_endpoint_agent(traj, env_info, task_info):
    """
    Verify agent deployment using exported JSON data.
    
    Criteria:
    1. Package installed (20 pts)
    2. Configuration correct (Manager IP) (20 pts)
    3. Agent Registered (present in API) (20 pts)
    4. Status Active (connected and sending keepalives) (40 pts)
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
        return {"passed": False, "score": 0, "feedback": f"Failed to load result: {str(e)}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback = []
    
    # Check 1: Package Installation (20 pts)
    if result.get('package_installed', False):
        score += 20
        feedback.append("Agent package installed.")
    else:
        feedback.append("Agent package NOT installed.")

    # Check 2: Local Configuration (20 pts)
    # Manager IP should be 127.0.0.1 or localhost
    manager_ip = result.get('config_manager_ip', '')
    if '127.0.0.1' in manager_ip or 'localhost' in manager_ip:
        score += 20
        feedback.append(f"Configuration points to correct Manager IP ({manager_ip}).")
    else:
        feedback.append(f"Configuration has incorrect Manager IP: '{manager_ip}'.")

    # Check 3: Registration (20 pts)
    # API status should not be 'not_found'
    api_status = result.get('api_agent_status', 'unknown')
    
    if api_status != 'not_found' and api_status != 'api_error' and api_status != 'unknown':
        score += 20
        feedback.append(f"Agent 'production-db-01' registered in Manager (ID: {result.get('api_agent_id')}).")
        
        # Check 4: Activity Status (40 pts)
        if api_status.lower() == 'active':
            score += 40
            feedback.append("Agent status is ACTIVE.")
        else:
            feedback.append(f"Agent registered but status is '{api_status}' (expected 'active'). Check connectivity or service status.")
    else:
        feedback.append("Agent NOT found in Manager API.")

    # Penalty if service is not running locally but API says active (unlikely, but ensures consistency)
    if not result.get('service_running', False) and score >= 80:
        feedback.append("WARNING: Service appears stopped locally despite active API status.")
        # We don't deduct points if API says active, as API is the source of truth for "connectedness"
        # The service check might fail if run inside a restricted container context, but API truth is paramount.

    passed = (score == 100)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }