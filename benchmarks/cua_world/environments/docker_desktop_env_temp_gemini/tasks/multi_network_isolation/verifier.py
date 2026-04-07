#!/usr/bin/env python3
"""
Verifier for multi_network_isolation task.

Criteria:
1. Networks 'frontend' and 'backend' exist (Bridge driver)
2. Container 'web-proxy' exists, running, correct image, ONLY on frontend
3. Container 'app-server' exists, running, correct image, on BOTH frontend and backend
4. Container 'data-store' exists, running, correct image, ONLY on backend
5. Containers created after task start (anti-gaming)
"""

import json
import tempfile
import os
import logging
from datetime import datetime

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def parse_docker_timestamp(ts_str):
    """Parse Docker timestamp string to unix timestamp."""
    try:
        # Docker format example: "2023-10-27T10:00:00.123456789Z"
        # Python 3.11+ supports ISO parsing easily, but we need to be robust
        if not ts_str:
            return 0
        # Truncate nanoseconds for compatibility
        ts_str = ts_str.split('.')[0] + 'Z'
        dt = datetime.strptime(ts_str, "%Y-%m-%dT%H:%M:%SZ")
        return dt.timestamp()
    except Exception as e:
        logger.warning(f"Failed to parse timestamp {ts_str}: {e}")
        return 0

def verify_multi_network_isolation(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load result JSON
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
    task_start = result.get('task_start_time', 0)
    
    # ------------------------------------------------------------------
    # 1. Verify Networks (20 points)
    # ------------------------------------------------------------------
    networks = result.get('networks', {})
    
    # Frontend Network
    frontend_net = networks.get('frontend')
    if frontend_net and isinstance(frontend_net, list) and len(frontend_net) > 0:
        # Docker inspect returns a list
        net_info = frontend_net[0]
        if net_info.get('Driver') == 'bridge':
            score += 10
            feedback_parts.append("Network 'frontend' exists (bridge)")
        else:
            score += 5
            feedback_parts.append("Network 'frontend' exists but wrong driver")
    else:
        feedback_parts.append("Network 'frontend' missing")

    # Backend Network
    backend_net = networks.get('backend')
    if backend_net and isinstance(backend_net, list) and len(backend_net) > 0:
        net_info = backend_net[0]
        if net_info.get('Driver') == 'bridge':
            score += 10
            feedback_parts.append("Network 'backend' exists (bridge)")
        else:
            score += 5
            feedback_parts.append("Network 'backend' exists but wrong driver")
    else:
        feedback_parts.append("Network 'backend' missing")

    # ------------------------------------------------------------------
    # 2. Verify Containers (80 points total)
    # ------------------------------------------------------------------
    containers = result.get('containers', {})
    
    # Helper to check container properties
    def check_container(name, expected_image_key, expected_nets, forbidden_nets):
        c_json = containers.get(name)
        local_score = 0
        local_feedback = []
        
        if not c_json or not isinstance(c_json, list) or len(c_json) == 0:
            return 0, [f"Container '{name}' missing"]

        info = c_json[0]
        
        # Check running state (5 pts)
        if info.get('State', {}).get('Running') is True:
            local_score += 5
            local_feedback.append(f"{name}: Running")
        else:
            local_feedback.append(f"{name}: Not running")
            
        # Check Image (5 pts)
        image = info.get('Config', {}).get('Image', '').lower()
        if expected_image_key in image:
            local_score += 5
        else:
            local_feedback.append(f"{name}: Wrong image ({image})")

        # Check Creation Time (Anti-gaming)
        created_str = info.get('Created')
        created_ts = parse_docker_timestamp(created_str)
        if created_ts < task_start:
            local_feedback.append(f"{name}: Created before task start (suspicious)")
            # Penalize or just warn? Let's treat as fail condition for that container
            return 0, [f"{name}: Pre-existing container detected"]

        # Check Network Membership (10-20 pts)
        net_settings = info.get('NetworkSettings', {}).get('Networks', {})
        connected_nets = list(net_settings.keys())
        
        # Check expected networks
        all_expected_present = True
        for net in expected_nets:
            if net in connected_nets:
                local_score += 5 # 5 pts per correct network
            else:
                all_expected_present = False
                local_feedback.append(f"{name}: Missing connection to {net}")
        
        # Check forbidden networks (isolation)
        isolation_broken = False
        for net in forbidden_nets:
            if net in connected_nets:
                isolation_broken = True
                local_feedback.append(f"{name}: Connected to FORBIDDEN network '{net}'")
        
        if isolation_broken:
            # Severe penalty for breaking isolation
            local_score = max(0, local_score - 10)
        
        return local_score, local_feedback

    # Check 'web-proxy' (Expected: frontend; Forbidden: backend)
    # Total possible: 5(run) + 5(img) + 5(frontend) + implied isolation check
    s, f = check_container('web-proxy', 'nginx', ['frontend'], ['backend'])
    score += s
    feedback_parts.extend(f)

    # Check 'app-server' (Expected: frontend, backend)
    # Total possible: 5(run) + 5(img) + 5(frontend) + 5(backend)
    s, f = check_container('app-server', 'httpd', ['frontend', 'backend'], [])
    score += s
    feedback_parts.extend(f)

    # Check 'data-store' (Expected: backend; Forbidden: frontend)
    # Total possible: 5(run) + 5(img) + 5(backend) + implied isolation check
    s, f = check_container('data-store', 'redis', ['backend'], ['frontend'])
    score += s
    feedback_parts.extend(f)
    
    # ------------------------------------------------------------------
    # 3. Final Assessment
    # ------------------------------------------------------------------
    # Max score calculation:
    # Networks: 20
    # Web-proxy: 15 (run+img+frontend)
    # App-server: 20 (run+img+frontend+backend)
    # Data-store: 15 (run+img+backend)
    # Total: 70? Wait, the math needs to sum to 100.
    
    # Let's adjust weights dynamically to map to 100 scale:
    # We have raw score. Let's normalize or just set the weights higher.
    # Current max raw: 20 + 15 + 20 + 15 = 70.
    # Let's add points for "Architecture Valid" if isolation is perfect.
    
    # Check Architecture Integrity (30 pts bonus)
    # web-proxy NOT on backend AND data-store NOT on frontend
    proxy_nets = containers.get('web-proxy', [{}])[0].get('NetworkSettings', {}).get('Networks', {}) if containers.get('web-proxy') else {}
    store_nets = containers.get('data-store', [{}])[0].get('NetworkSettings', {}).get('Networks', {}) if containers.get('data-store') else {}
    
    perfect_isolation = True
    if 'backend' in proxy_nets: perfect_isolation = False
    if 'frontend' in store_nets: perfect_isolation = False
    
    # Also check if they are actually running to award architecture points
    web_running = containers.get('web-proxy', [{}])[0].get('State', {}).get('Running') if containers.get('web-proxy') else False
    data_running = containers.get('data-store', [{}])[0].get('State', {}).get('Running') if containers.get('data-store') else False

    if perfect_isolation and web_running and data_running:
        score += 30
        feedback_parts.append("Architecture isolation verified (+30)")
    else:
        feedback_parts.append("Architecture isolation failed or containers not running")

    return {
        "passed": score >= 70,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }