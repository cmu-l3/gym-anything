#!/usr/bin/env python3
"""
Verifier for convert_run_to_compose task.
Checks if the agent correctly converted docker run commands to docker-compose.yml
and successfully started the stack.
"""

import json
import os
import tempfile
import base64

def verify_convert_run_to_compose(traj, env_info, task_info):
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
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback_parts = []
    
    # 1. Compose File Existence & Validity (10 pts)
    if result.get('compose_exists') and result.get('compose_valid'):
        score += 10
        feedback_parts.append("Valid docker-compose.yml created")
    else:
        feedback_parts.append("docker-compose.yml missing or invalid")

    # 2. Services Running (20 pts)
    # Must have prometheus, grafana, node-exporter (or node-exporter)
    running_services = result.get('running_services', '').split(',')
    required_services = {'prometheus', 'grafana', 'node-exporter'}
    
    # Handle potential service name variations (e.g. node_exporter vs node-exporter)
    running_set = set(s for s in running_services if s)
    # Check for node-exporter variation
    if 'node_exporter' in running_set:
        running_set.remove('node_exporter')
        running_set.add('node-exporter')

    missing = required_services - running_set
    if not missing:
        score += 20
        feedback_parts.append("All services running")
    else:
        feedback_parts.append(f"Missing running services: {', '.join(missing)}")

    # 3. HTTP Endpoints (Functional Check) (25 pts)
    http_scores = 0
    endpoints = result.get('http_endpoints', {})
    
    if endpoints.get('prometheus') == "200":
        http_scores += 10
    if endpoints.get('grafana') == "200":
        http_scores += 10
    if endpoints.get('node_exporter') == "200":
        http_scores += 5
        
    score += http_scores
    if http_scores == 25:
        feedback_parts.append("All endpoints accessible")
    else:
        feedback_parts.append(f"Endpoints checks failed (Score: {http_scores}/25)")

    # 4. Configuration Fidelity (35 pts)
    # We inspect the actual running containers to see if they match the requirements
    configs = result.get('container_configs', {})
    config_score = 0
    
    # Prometheus Config
    prom = configs.get('prometheus', {})
    if prom:
        # Check restart policy
        if prom.get('HostConfig', {}).get('RestartPolicy', {}).get('Name') == 'unless-stopped':
            config_score += 2.5
        # Check volumes/binds
        mounts = prom.get('Mounts', [])
        has_data_vol = any(m['Type'] == 'volume' and 'prometheus-data' in m['Name'] for m in mounts)
        has_config_bind = any(m['Type'] == 'bind' and 'prometheus.yml' in m['Source'] for m in mounts)
        if has_data_vol: config_score += 2.5
        if has_config_bind: config_score += 2.5
        # Check ports
        ports = prom.get('NetworkSettings', {}).get('Ports', {})
        if '9090/tcp' in ports: config_score += 2.5

    # Grafana Config
    graf = configs.get('grafana', {})
    if graf:
        if graf.get('HostConfig', {}).get('RestartPolicy', {}).get('Name') == 'unless-stopped':
            config_score += 2.5
        mounts = graf.get('Mounts', [])
        if any(m['Type'] == 'volume' and 'grafana-data' in m['Name'] for m in mounts):
            config_score += 2.5
        ports = graf.get('NetworkSettings', {}).get('Ports', {})
        if '3000/tcp' in ports: config_score += 2.5
        # Check Envs
        env = graf.get('Config', {}).get('Env', [])
        if any('GF_SECURITY_ADMIN_PASSWORD=monitoring123' in e for e in env):
            config_score += 2.5

    # Node Exporter Config
    node = configs.get('node_exporter', {})
    if node:
        if node.get('HostConfig', {}).get('RestartPolicy', {}).get('Name') == 'unless-stopped':
            config_score += 5
        if node.get('HostConfig', {}).get('PidMode') == 'host':
            config_score += 5
        # Port check
        ports = node.get('NetworkSettings', {}).get('Ports', {})
        if '9100/tcp' in ports: config_score += 5

    score += int(config_score)
    feedback_parts.append(f"Configuration fidelity: {int(config_score)}/35")

    # 5. Prometheus Scraping (10 pts)
    if result.get('prometheus_targets_up'):
        score += 10
        feedback_parts.append("Prometheus scraping active")
    else:
        feedback_parts.append("Prometheus not scraping targets")

    # Final Pass Logic
    # Must have valid compose, all services running, and basic endpoints working
    passed = (
        result.get('compose_valid') and 
        not missing and 
        score >= 70
    )

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }