#!/usr/bin/env python3
"""
Verifier for technician_group_routing_configuration task.

Scoring breakdown (100 pts total, pass threshold: 60):
  Criterion 1 (20 pts): 'Network Operations Team' group exists.
  Criterion 2 (20 pts): 'Hardware Support Team' group exists.
  Criterion 3 (20 pts): New technician Maya Patel exists (was not in baseline).
  Criterion 4 (20 pts): New technician Carlos Rivera exists (was not in baseline).
  Criterion 5 (10 pts): Ticket 1004 (VPN) assigned to 'Network Operations Team' group.
  Criterion 6 (10 pts): Ticket 1001 (Keyboard) assigned to 'Hardware Support Team' group.

Wrong-target gate: If neither new group was created, return score=0 (agent did nothing
relevant — creating groups is the core deliverable that everything else depends on).
"""

import json
import tempfile
import os
import logging

logger = logging.getLogger(__name__)

PASS_THRESHOLD = 60


def verify_technician_group_routing_configuration(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')

    if copy_from_env is None:
        return {
            "passed": False,
            "score": 0,
            "feedback": "Verifier error: copy_from_env not available."
        }

    with tempfile.TemporaryDirectory() as tmp_dir:
        result_path = os.path.join(tmp_dir, 'result.json')
        try:
            copy_from_env('/tmp/technician_group_routing_configuration_result.json', result_path)
            with open(result_path) as f:
                data = json.load(f)
        except Exception as e:
            return {
                "passed": False,
                "score": 0,
                "feedback": f"Could not read result file from VM: {e}"
            }

    score = 0
    feedback_parts = []
    subscores = {}

    network_group = data.get('network_group_found', False)
    hardware_group = data.get('hardware_group_found', False)

    # --- Wrong-target gate: if no groups were created, nothing meaningful was done ---
    if not network_group and not hardware_group:
        return {
            "passed": False,
            "score": 0,
            "feedback": (
                "FAIL: Neither 'Network Operations Team' nor 'Hardware Support Team' groups were found. "
                "The agent must create both technician groups as the core deliverable of this task."
            ),
            "subscores": {
                "network_group": 0,
                "hardware_group": 0,
                "maya_patel": 0,
                "carlos_rivera": 0,
                "vpn_ticket_routing": 0,
                "keyboard_ticket_routing": 0
            }
        }

    # --- Criterion 1: Network Operations Team exists ---
    if network_group:
        score += 20
        subscores['network_group'] = 20
        feedback_parts.append("PASS: 'Network Operations Team' group created. (+20 pts)")
    else:
        subscores['network_group'] = 0
        feedback_parts.append("FAIL: 'Network Operations Team' group not found. (+0 pts)")

    # --- Criterion 2: Hardware Support Team exists ---
    if hardware_group:
        score += 20
        subscores['hardware_group'] = 20
        feedback_parts.append("PASS: 'Hardware Support Team' group created. (+20 pts)")
    else:
        subscores['hardware_group'] = 0
        feedback_parts.append("FAIL: 'Hardware Support Team' group not found. (+0 pts)")

    # --- Criterion 3: Maya Patel exists ---
    maya_found = data.get('maya_patel_found', False)
    if maya_found:
        score += 20
        subscores['maya_patel'] = 20
        feedback_parts.append("PASS: Technician 'Maya Patel' created. (+20 pts)")
    else:
        subscores['maya_patel'] = 0
        feedback_parts.append(
            "FAIL: Technician 'Maya Patel' not found in the system. "
            f"(SQL count: {data.get('maya_count_sql', 0)}, API found: {data.get('maya_patel_found_api', False)})"
        )

    # --- Criterion 4: Carlos Rivera exists ---
    carlos_found = data.get('carlos_rivera_found', False)
    if carlos_found:
        score += 20
        subscores['carlos_rivera'] = 20
        feedback_parts.append("PASS: Technician 'Carlos Rivera' created. (+20 pts)")
    else:
        subscores['carlos_rivera'] = 0
        feedback_parts.append(
            "FAIL: Technician 'Carlos Rivera' not found in the system. "
            f"(SQL count: {data.get('carlos_count_sql', 0)}, API found: {data.get('carlos_rivera_found_api', False)})"
        )

    # --- Criterion 5: VPN ticket (1004) routed to Network Operations Team ---
    vpn_routed = data.get('ticket_1004_network_group', False)
    if vpn_routed:
        score += 10
        subscores['vpn_ticket_routing'] = 10
        feedback_parts.append(
            f"PASS: VPN ticket (1004) assigned to Network Operations Team group. "
            f"(group: '{data.get('ticket_1004_group_name', '')}') (+10 pts)"
        )
    else:
        subscores['vpn_ticket_routing'] = 0
        feedback_parts.append(
            f"FAIL: VPN ticket (1004) not assigned to 'Network Operations Team'. "
            f"Current group: '{data.get('ticket_1004_group_name', 'none')}' (+0 pts)"
        )

    # --- Criterion 6: Keyboard ticket (1001) routed to Hardware Support Team ---
    keyboard_routed = data.get('ticket_1001_hardware_group', False)
    if keyboard_routed:
        score += 10
        subscores['keyboard_ticket_routing'] = 10
        feedback_parts.append(
            f"PASS: Keyboard ticket (1001) assigned to Hardware Support Team group. "
            f"(group: '{data.get('ticket_1001_group_name', '')}') (+10 pts)"
        )
    else:
        subscores['keyboard_ticket_routing'] = 0
        feedback_parts.append(
            f"FAIL: Keyboard ticket (1001) not assigned to 'Hardware Support Team'. "
            f"Current group: '{data.get('ticket_1001_group_name', 'none')}' (+0 pts)"
        )

    passed = score >= PASS_THRESHOLD
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts),
        "subscores": subscores
    }
