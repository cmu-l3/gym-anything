#!/usr/bin/env python3
"""
Verifier for diagrams.net create_network_diagram task.
Checks if a network topology diagram was created with the required elements.
"""

import json
import tempfile
import os
import logging

logging.basicConfig(level=logging.DEBUG)


def verify_create_network_diagram(traj, env_info, task_info):
    """
    Verify that a network topology diagram was created successfully.

    Checks:
    1. Diagram file exists and was saved
    2. Diagram contains sufficient shapes (min 6)
    3. Diagram contains connections between devices (min 5)
    4. Diagram has required network elements (cloud, router, switch, computers, server)
    """

    # Get copy function from framework
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {
            "passed": False,
            "score": 0,
            "feedback": "Copy function not available"
        }

    # Get expected values from task metadata
    metadata = task_info.get('metadata', {})
    min_shapes = metadata.get('min_shapes', 6)
    min_connections = metadata.get('min_connections', 5)

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
            "feedback": f"Failed to read result: {e}"
        }
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    # Initialize scoring
    score = 0
    feedback_parts = []
    criteria_met = 0
    total_criteria = 8

    # Criterion 1: File exists (15 points)
    if result.get('file_exists'):
        score += 15
        criteria_met += 1
        feedback_parts.append(f"File exists: {result.get('file_path', 'unknown')}")
    else:
        feedback_parts.append("FAIL: No diagram file found")
        return {
            "passed": False,
            "score": 0,
            "feedback": " | ".join(feedback_parts)
        }

    # Criterion 2: File size indicates content (10 points)
    file_size = result.get('file_size', 0)
    if file_size > 1000:
        score += 10
        criteria_met += 1
        feedback_parts.append(f"File size OK: {file_size} bytes")
    else:
        feedback_parts.append(f"File too small: {file_size} bytes")

    # Criterion 3: Sufficient shapes (15 points)
    num_shapes = result.get('num_shapes', 0)
    if num_shapes >= min_shapes:
        score += 15
        criteria_met += 1
        feedback_parts.append(f"Shapes: {num_shapes}/{min_shapes}")
    elif num_shapes >= min_shapes // 2:
        score += 7
        feedback_parts.append(f"Partial shapes: {num_shapes}/{min_shapes}")
    else:
        feedback_parts.append(f"Insufficient shapes: {num_shapes}/{min_shapes}")

    # Criterion 4: Connections between devices (15 points)
    num_connections = result.get('num_connections', 0)
    if num_connections >= min_connections:
        score += 15
        criteria_met += 1
        feedback_parts.append(f"Connections: {num_connections}/{min_connections}")
    elif num_connections >= min_connections // 2:
        score += 7
        feedback_parts.append(f"Partial connections: {num_connections}/{min_connections}")
    else:
        feedback_parts.append(f"Insufficient connections: {num_connections}/{min_connections}")

    # Criterion 5: Has cloud/internet element (10 points)
    has_cloud = result.get('has_cloud') or result.get('has_internet_text')
    if has_cloud:
        score += 10
        criteria_met += 1
        feedback_parts.append("Has Internet/Cloud")
    else:
        feedback_parts.append("Missing Internet/Cloud")

    # Criterion 6: Has router/firewall (10 points)
    has_router = result.get('has_router') or result.get('has_router_text')
    if has_router:
        score += 10
        criteria_met += 1
        feedback_parts.append("Has Router/Firewall")
    else:
        feedback_parts.append("Missing Router/Firewall")

    # Criterion 7: Has switch (10 points)
    has_switch = result.get('has_switch') or result.get('has_switch_text')
    if has_switch:
        score += 10
        criteria_met += 1
        feedback_parts.append("Has Switch")
    else:
        feedback_parts.append("Missing Switch")

    # Criterion 8: Has computers (at least 3) and server (15 points)
    has_computer = result.get('has_computer') or result.get('has_computer_text')
    num_computers = result.get('num_computers', 0)
    has_server = result.get('has_server') or result.get('has_server_text')

    # Task requires PC1, PC2, PC3 (3 computers) and 1 server
    has_enough_computers = num_computers >= 3

    if has_enough_computers and has_server:
        score += 15
        criteria_met += 1
        feedback_parts.append(f"Has {num_computers} Computers and Server")
    elif has_computer and has_server:
        # Has at least 1 computer and server, but not enough computers
        score += 10
        feedback_parts.append(f"Has {num_computers}/3 Computers and Server")
    elif has_computer or has_server:
        score += 5
        if has_computer:
            feedback_parts.append(f"Has {num_computers} Computers (missing Server)")
        else:
            feedback_parts.append("Has Server (missing Computers)")
    else:
        feedback_parts.append("Missing Computers and Server")

    # Determine pass/fail
    # CRITICAL: Must have minimum connections to pass - a network diagram without connections is invalid
    has_minimum_connections = num_connections >= 3  # At least 3 network lines
    has_minimum_shapes = num_shapes >= min_shapes
    has_core_elements = has_router and has_switch  # Router and switch are essential
    has_all_endpoints = has_enough_computers and has_server  # Need 3 PCs and server

    # Pass requires:
    # 1. Score >= 70 (stricter threshold)
    # 2. At least 6 criteria met
    # 3. At least 3 connections (network lines)
    # 4. Core network elements (router, switch)
    # 5. At least 3 computers and 1 server
    passed = (score >= 70 and
              criteria_met >= 6 and
              has_minimum_connections and
              has_core_elements and
              has_all_endpoints)

    if passed:
        if score >= 90:
            feedback_parts.append("Excellent network diagram!")
        elif score >= 80:
            feedback_parts.append("Good network diagram!")
        else:
            feedback_parts.append("Acceptable network diagram")
    else:
        # Provide specific failure reasons
        failure_reasons = []
        if not has_minimum_connections:
            failure_reasons.append(f"need at least 3 connections (have {num_connections})")
        if not has_core_elements:
            missing = []
            if not has_router:
                missing.append("router")
            if not has_switch:
                missing.append("switch")
            failure_reasons.append(f"missing core elements: {', '.join(missing)}")
        if not has_all_endpoints:
            missing = []
            if not has_enough_computers:
                missing.append(f"need 3 PCs (have {num_computers})")
            if not has_server:
                missing.append("server")
            failure_reasons.append(f"missing endpoints: {', '.join(missing)}")
        if score < 70:
            failure_reasons.append(f"score {score} < 70")
        if criteria_met < 6:
            failure_reasons.append(f"only {criteria_met}/6 criteria met")

        feedback_parts.append(f"FAILED: {'; '.join(failure_reasons)}")

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts),
        "subscores": {
            "file_exists": result.get('file_exists', False),
            "num_shapes": num_shapes,
            "num_connections": num_connections,
            "criteria_met": criteria_met,
            "total_criteria": total_criteria
        }
    }
