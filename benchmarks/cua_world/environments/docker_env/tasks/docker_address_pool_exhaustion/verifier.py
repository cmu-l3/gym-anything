#!/usr/bin/env python3
import json
import os
import logging
import tempfile
import ipaddress

logger = logging.getLogger(__name__)

def verify_docker_address_pool_exhaustion(traj, env_info, task_info):
    """
    Verifies that the agent:
    1. Modified /etc/docker/daemon.json to expand address pools.
    2. Successfully restarted Docker.
    3. Recovered the Prod container.
    4. Successfully launched the Test container.
    """
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
        return {"passed": False, "score": 0, "feedback": f"Failed to load result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback = []

    # 1. Daemon Configuration (30 pts)
    # Must be modified AND contain valid expanded pool
    config_valid = False
    config_content = result.get("daemon_config", "")
    config_modified = result.get("config_modified", False)
    
    if not config_modified:
        feedback.append("FAIL: daemon.json was not modified.")
    else:
        try:
            cfg = json.loads(config_content)
            pools = cfg.get("default-address-pools", [])
            if not pools:
                feedback.append("FAIL: daemon.json missing 'default-address-pools'.")
            else:
                # Check the first pool logic
                pool = pools[0]
                base = pool.get("base", "")
                size = int(pool.get("size", 32))
                
                # Logic: Is the pool big enough? 
                # Restrictive was: base="192.168.200.0/24", size=24 (Capacity: 1 network)
                # We want capacity > 1.
                
                try:
                    network = ipaddress.ip_network(base, strict=False)
                    # Capacity = 2^(size - prefix_len)
                    # If prefix_len (e.g. 8) < size (e.g. 24), we have room for networks.
                    if size > network.prefixlen:
                        config_valid = True
                        score += 30
                        feedback.append("PASS: daemon.json pool expanded successfully.")
                    else:
                        feedback.append(f"FAIL: Pool size ({size}) <= Base CIDR prefix ({network.prefixlen}). Still restrictive.")
                except ValueError:
                    feedback.append("FAIL: Invalid CIDR in 'base'.")
        except json.JSONDecodeError:
            feedback.append("FAIL: daemon.json is not valid JSON.")

    # 2. Docker Daemon Health (10 pts)
    if result.get("docker_running", False):
        score += 10
        feedback.append("PASS: Docker daemon is running.")
    else:
        feedback.append("FAIL: Docker daemon is not running.")

    # 3. Prod Container Status (20 pts)
    if result.get("prod_running", False):
        score += 20
        feedback.append("PASS: acme-prod is running.")
    else:
        feedback.append("FAIL: acme-prod is not running.")

    # 4. Test Container Status (30 pts)
    if result.get("test_running", False):
        score += 30
        feedback.append("PASS: acme-ci-test is running.")
    else:
        feedback.append("FAIL: acme-ci-test is not running.")

    # 5. Network Isolation/Validity (10 pts)
    prod_ip = result.get("prod_ip", "")
    test_ip = result.get("test_ip", "")
    
    if prod_ip and test_ip and prod_ip != test_ip:
        # Check if they are in similar private ranges but distinct
        score += 10
        feedback.append("PASS: Containers have distinct IP allocations.")
    elif not prod_ip or not test_ip:
        feedback.append("FAIL: One or both containers have no IP address.")

    passed = (score >= 70) and config_valid and result.get("prod_running") and result.get("test_running")

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }