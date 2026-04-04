#!/usr/bin/env python3
"""Verifier for deploy_voting_app task.

This task deploys the Docker Example Voting App, a real-world
multi-container application from https://github.com/dockersamples/example-voting-app

Note: This verifier checks the final state (all 5 services running with web UIs accessible)
but cannot verify whether the agent used Docker Desktop features vs pure CLI.
Future enhancement could analyze the trajectory for GUI interactions
(using Docker Desktop's compose features, container group views, etc.)
to enforce GUI usage.
"""

import json
import tempfile
import os


def verify_deploy_voting_app(traj, env_info, task_info):
    """Verify the Docker Voting App was deployed successfully.

    Criteria:
    - Docker Desktop is running (10 points)
    - Docker daemon is ready (10 points)
    - All 5 services are running (50 points - 10 each)
    - Vote web interface accessible (15 points)
    - Result web interface accessible (15 points)
    """

    # Get copy function from framework
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {
            "passed": False,
            "score": 0,
            "feedback": "Copy function not available from framework"
        }

    # Get expected values from task metadata
    metadata = task_info.get('metadata', {})
    expected_count = metadata.get('expected_container_count', 5)
    expected_services = metadata.get('expected_services', ['vote', 'result', 'worker', 'redis', 'db'])

    # Copy result file from container
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Failed to read task result: {e}"
        }
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    # Calculate score
    score = 0
    feedback_parts = []
    details = {}

    # Docker Desktop running (10 points)
    if result.get('docker_desktop_running', False):
        score += 10
        feedback_parts.append("Docker Desktop: running")
    else:
        feedback_parts.append("Docker Desktop: NOT running")

    # Docker daemon ready (10 points)
    if result.get('docker_daemon_ready', False):
        score += 10
        feedback_parts.append("Docker daemon: ready")
    else:
        feedback_parts.append("Docker daemon: NOT ready")

    # Check each service (10 points each, 50 total)
    services = result.get('services', {})
    running_services = []
    missing_services = []

    for service in expected_services:
        if services.get(service, False):
            score += 10
            running_services.append(service)
        else:
            missing_services.append(service)

    details['running_services'] = running_services
    details['missing_services'] = missing_services
    details['services_count'] = len(running_services)

    if missing_services:
        feedback_parts.append(f"Services running: {len(running_services)}/5 (missing: {', '.join(missing_services)})")
    else:
        feedback_parts.append(f"Services running: {len(running_services)}/5 (all services up)")

    # Vote web interface (15 points)
    web_interfaces = result.get('web_interfaces', {})
    if web_interfaces.get('vote_accessible', False):
        score += 15
        feedback_parts.append("Vote UI: accessible")
    else:
        http_code = web_interfaces.get('vote_http_code', 'N/A')
        feedback_parts.append(f"Vote UI: NOT accessible (HTTP {http_code})")

    # Result web interface (15 points)
    if web_interfaces.get('result_accessible', False):
        score += 15
        feedback_parts.append("Result UI: accessible")
    else:
        http_code = web_interfaces.get('result_http_code', 'N/A')
        feedback_parts.append(f"Result UI: NOT accessible (HTTP {http_code})")

    # Check compose project health
    compose_healthy = result.get('compose_project_healthy', False)
    if compose_healthy:
        feedback_parts.append("Compose project: healthy")
    else:
        feedback_parts.append("Compose project: not detected via docker-compose")

    # Determine pass/fail
    # Pass requires: all 5 services running AND both web interfaces accessible
    passed = (len(running_services) >= 5 and
              web_interfaces.get('vote_accessible', False) and
              web_interfaces.get('result_accessible', False))

    details['voting_app_services_running'] = result.get('voting_app_services_running', 0)
    details['compose_project_healthy'] = compose_healthy
    details['running_containers'] = result.get('running_containers', '')

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts),
        "details": details
    }
