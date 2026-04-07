#!/usr/bin/env python3
"""
Verifier for docker_remote_context_setup task.

Scoring (100 points):
- Context 'prod' created: 15 pts
- Host URL correct (tcp://IP:2376): 15 pts
- TLS verification enabled and paths set: 20 pts
- Connection successful (functional test): 25 pts
- Workload running on REMOTE node: 25 pts
"""

import json
import tempfile
import os
import logging
import re

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_docker_remote_context_setup(traj, env_info, task_info):
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
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback_parts = []
    
    # 1. Context Exists (15 pts)
    if result.get('context_exists'):
        score += 15
        feedback_parts.append("Context 'prod' exists (+15)")
    else:
        feedback_parts.append("Context 'prod' not found")
        return {"passed": False, "score": 0, "feedback": " | ".join(feedback_parts)}

    # 2. Host URL (15 pts)
    host_url = result.get('host_url', '')
    remote_ip = result.get('remote_ip_expected', '0.0.0.0')
    
    # Accept explicit IP or 'prod-node' hostname if they mapped it in /etc/hosts (advanced)
    # The crucial part is port 2376 and tcp protocol
    if '2376' in host_url and ('tcp://' in host_url) and (remote_ip in host_url or 'prod-node' in host_url):
        score += 15
        feedback_parts.append(f"Host URL correct: {host_url} (+15)")
    else:
        feedback_parts.append(f"Host URL incorrect or missing port 2376: {host_url}")

    # 3. TLS Configuration (20 pts)
    # Check if TLS paths are set and skip_tls_verify is false
    skip_tls = str(result.get('skip_tls_verify', 'false')).lower()
    ca = result.get('ca_path')
    cert = result.get('cert_path')
    key = result.get('key_path')
    
    if skip_tls == 'false' and ca and cert and key:
        score += 20
        feedback_parts.append("TLS configuration valid (+20)")
    else:
        feedback_parts.append("TLS configuration missing or insecure (SkipTLSVerify=true or missing certs)")

    # 4. Connection Success (25 pts)
    if result.get('connection_success'):
        score += 25
        feedback_parts.append("Connection to remote daemon successful (+25)")
    else:
        feedback_parts.append("Could not connect to remote daemon using the context")

    # 5. Remote Workload (25 pts)
    # MUST be on remote, MUST NOT be on local (unless they named it differently, but verification checks specific name)
    remote_running = result.get('remote_workload_running')
    local_running = result.get('local_workload_running')
    
    if remote_running:
        score += 25
        feedback_parts.append("Workload 'prod-web' running on remote node (+25)")
    elif local_running:
        feedback_parts.append("Workload 'prod-web' found on LOCAL node (Incorrect target) (0)")
    else:
        feedback_parts.append("Workload 'prod-web' not found on remote node")

    passed = score >= 75
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }