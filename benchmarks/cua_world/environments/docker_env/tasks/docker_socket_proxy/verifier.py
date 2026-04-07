#!/usr/bin/env python3
"""
Verifier for docker_socket_proxy task.

Scoring Criteria (100 points total):
1. Dashboard Hardening (20 pts): Dashboard service no longer mounts /var/run/docker.sock.
2. Proxy Architecture (20 pts): A proxy service exists and mounts the socket.
3. Allowed Access (20 pts): Proxy allows GET /containers/json (returns 200).
4. Blocked Methods (20 pts): Proxy blocks POST requests (returns 403/401/405).
5. Blocked Paths (10 pts): Proxy blocks sensitive paths like /secrets.
6. System Health (10 pts): Dashboard app is successfully reading data via the proxy.

Pass Threshold: 70 points
"""

import json
import tempfile
import os
import logging

logger = logging.getLogger(__name__)

def verify_docker_socket_proxy(traj, env_info, task_info):
    """Verify the implementation of the Docker socket proxy sidecar."""
    copy_from_env = env_info.get("copy_from_env")
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env unavailable"}

    try:
        temp_file = tempfile.NamedTemporaryFile(delete=False, suffix=".json")
        temp_path = temp_file.name
        temp_file.close()

        try:
            copy_from_env("/tmp/socket_proxy_result.json", temp_path)
            with open(temp_path, "r") as f:
                result = json.load(f)
        finally:
            try:
                os.unlink(temp_path)
            except Exception:
                pass
    except FileNotFoundError:
        return {"passed": False, "score": 0, "feedback": "Result file not found"}
    except json.JSONDecodeError:
        return {"passed": False, "score": 0, "feedback": "Result JSON malformed"}
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Error: {e}"}

    score = 0
    feedback_parts = []
    
    # 1. Dashboard Hardening (20 pts)
    socket_removed = result.get("socket_removed_from_dashboard", False)
    if socket_removed:
        score += 20
        feedback_parts.append("Dashboard socket removed (+20)")
    else:
        feedback_parts.append("Dashboard still mounts raw socket (0/20)")

    # 2. Proxy Architecture (20 pts)
    proxy_running = result.get("proxy_running", False)
    proxy_has_socket = result.get("proxy_has_socket", False)
    if proxy_running and proxy_has_socket:
        score += 20
        feedback_parts.append("Proxy running with socket (+20)")
    elif proxy_running:
        score += 10
        feedback_parts.append("Proxy running but socket missing (10/20)")
    else:
        feedback_parts.append("Proxy container not running (0/20)")

    # 3. Allowed Access (20 pts)
    # Expect 200 OK
    allowed_code = str(result.get("test_allowed_code", "000"))
    if allowed_code == "200":
        score += 20
        feedback_parts.append("Allowed endpoint working (+20)")
    else:
        feedback_parts.append(f"Allowed endpoint failed (HTTP {allowed_code}) (0/20)")

    # 4. Blocked Methods (20 pts)
    # Expect 403 Forbidden, 401 Unauthorized, or 405 Method Not Allowed
    blocked_method_code = str(result.get("test_blocked_method_code", "000"))
    if blocked_method_code in ["403", "401", "405"]:
        score += 20
        feedback_parts.append("POST requests blocked (+20)")
    elif blocked_method_code == "200":
        feedback_parts.append("POST requests wrongly allowed (200 OK) (0/20)")
    else:
        # e.g. "000" (connection refused) means proxy might be down, partial credit if architecture is ok
        if proxy_running:
            feedback_parts.append(f"POST request check failed cleanly ({blocked_method_code}) (5/20)")
            score += 5
        else:
            feedback_parts.append(f"POST request check failed ({blocked_method_code}) (0/20)")

    # 5. Blocked Paths (10 pts)
    blocked_path_code = str(result.get("test_blocked_path_code", "000"))
    if blocked_path_code in ["403", "401"]:
        score += 10
        feedback_parts.append("Sensitive paths blocked (+10)")
    elif blocked_path_code == "404":
        # 404 is acceptable if the filter allows the request to pass to docker and docker returns 404
        # BUT the goal is to filter AT the proxy. If passed to docker, docker returns 404 for /secrets.
        # Ideally we want the proxy to deny it. However, strict adherence might fail good solutions.
        # Let's check strictness: Task says "blocking all other... paths".
        feedback_parts.append("Sensitive path passed to Docker (404) instead of blocked (403) (5/10)")
        score += 5
    elif blocked_path_code == "200":
        feedback_parts.append("Sensitive path allowed! (0/10)")
    else:
        feedback_parts.append(f"Sensitive path check code: {blocked_path_code} (0/10)")

    # 6. System Health (10 pts)
    logs_success = result.get("dashboard_logs_success", False)
    if logs_success:
        score += 10
        feedback_parts.append("Dashboard functioning (+10)")
    else:
        feedback_parts.append("Dashboard logs show failure or silence (0/10)")

    passed = score >= 70
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }