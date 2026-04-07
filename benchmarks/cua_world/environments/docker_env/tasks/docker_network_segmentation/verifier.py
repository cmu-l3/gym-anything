#!/usr/bin/env python3
"""
Verifier for Docker Network Segmentation Task.

Logic:
1. Validates existence of dmz-net, app-net, data-net.
2. Checks container memberships against the strict matrix:
   - Proxy: dmz-net only
   - Api: dmz-net, app-net
   - Users/Orders: app-net, data-net
   - Db/Cache: data-net only
3. Verifies actual network isolation via connectivity results (nc/curl).
4. Checks for documentation.
"""

import json
import base64
import os
import tempfile

def verify_docker_network_segmentation(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System Error: copy_from_env missing"}

    # Load result
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

    # 1. Network Existence (10 pts)
    nets = result.get("networks", {})
    if nets.get("dmz_net") and nets.get("app_net") and nets.get("data_net"):
        score += 10
        feedback.append("All 3 required networks exist.")
    else:
        feedback.append("Missing one or more required networks.")

    # 2. Container Membership (48 pts - 8 per container)
    # Expected topology mapping
    expected = {
        "/acme-proxy":  {"dmz-net"},
        "/acme-api":    {"dmz-net", "app-net"},
        "/acme-users":  {"app-net", "data-net"},
        "/acme-orders": {"app-net", "data-net"},
        "/acme-db":     {"data-net"},
        "/acme-cache":  {"data-net"}
    }
    
    # Map inspect data to simplified structure: {name: set(network_names)}
    actual_config = {}
    inspect_data = result.get("inspect_data", [])
    for container in inspect_data:
        name = container.get("Name")  # usually "/name"
        net_settings = container.get("NetworkSettings", {}).get("Networks", {})
        actual_config[name] = set(net_settings.keys())

    for c_name, expected_nets in expected.items():
        actual_nets = actual_config.get(c_name, set())
        
        # We need to map the actual network names (which might be project prefixed e.g. acme-platform_dmz-net)
        # However, the task description asked for specific names. If used in compose with 'name:', they are exact.
        # If standard compose, they are project_network. 
        # But 'setup_task.sh' cleared networks, so we look for substrings or exact matches if defined externally.
        # The prompt asked to "Create three specific networks... dmz-net".
        # Let's normalize actual nets by checking if the expected key is contained in the actual name.
        
        # Simpler approach: Check if 'acme-flat' is GONE and expected nets are PRESENT.
        
        has_correct = True
        # Check for required
        for req in expected_nets:
            if not any(req in act for act in actual_nets):
                has_correct = False
        
        # Check for forbidden (acme-flat) or cross-contamination
        # e.g. Proxy shouldn't have data-net
        forbidden_map = {
            "/acme-proxy":  ["data-net", "app-net", "acme-flat"],
            "/acme-api":    ["data-net", "acme-flat"],
            "/acme-users":  ["dmz-net", "acme-flat"],
            "/acme-orders": ["dmz-net", "acme-flat"],
            "/acme-db":     ["dmz-net", "app-net", "acme-flat"],
            "/acme-cache":  ["dmz-net", "app-net", "acme-flat"]
        }
        
        for forb in forbidden_map.get(c_name, []):
            if any(forb in act for act in actual_nets):
                has_correct = False

        if has_correct:
            score += 8
        else:
            feedback.append(f"{c_name} network config incorrect.")

    # 3. Running Status (7 pts)
    # 6 containers * ~1.16 pts, rounded to 7 for all up
    running = result.get("running_count", 0)
    if running == 6:
        score += 7
        feedback.append("All containers running.")
    else:
        feedback.append(f"Only {running}/6 containers running.")

    # 4. Isolation Checks (15 pts)
    # Proxy -> DB Isolation (8)
    # Proxy -> Cache Isolation (7)
    conn = result.get("connectivity", {})
    if conn.get("isolation_proxy_db") == "isolated":
        score += 8
    else:
        feedback.append("FAIL: Proxy can reach Database.")
        
    if conn.get("isolation_proxy_cache") == "isolated":
        score += 7
    else:
        feedback.append("FAIL: Proxy can reach Cache.")

    # 5. Connectivity Checks (10 pts)
    if conn.get("conn_proxy_api") == "connected":
        score += 5
    else:
        feedback.append("FAIL: Proxy cannot reach API.")

    if conn.get("conn_users_db") == "connected":
        score += 5
    else:
        feedback.append("FAIL: Users svc cannot reach DB.")

    # 6. Documentation (5 pts)
    doc = result.get("documentation", {})
    if doc.get("exists"):
        content = base64.b64decode(doc.get("content_b64", "")).decode('utf-8', errors='ignore').lower()
        if "dmz" in content and "data" in content and int(doc.get("mtime", 0)) > result.get("task_start", 0):
            score += 5
            feedback.append("Architecture doc valid.")
        else:
            feedback.append("Architecture doc incomplete or old.")
    else:
        feedback.append("No architecture doc found.")

    # 7. End-to-End (5 pts)
    if str(conn.get("http_status")) == "200":
        score += 5
    else:
        feedback.append(f"End-to-End HTTP check failed: {conn.get('http_status')}")

    passed = score >= 65
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }