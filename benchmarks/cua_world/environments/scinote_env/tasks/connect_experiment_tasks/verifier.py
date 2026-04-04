#!/usr/bin/env python3
"""Verifier for connect_experiment_tasks task."""

import json
import tempfile
import os


def verify_connect_experiment_tasks(traj, env_info, task_info):
    """Verify that three tasks were connected into a sequential workflow."""

    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/connect_tasks_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback_parts = []

    initial_count = int(result.get('initial_connection_count', 0))
    current_count = int(result.get('current_connection_count', 0))
    conn_1_2 = result.get('connection_1_to_2', False)
    conn_2_3 = result.get('connection_2_to_3', False)
    all_connections = result.get('all_connections', [])

    # Criterion 1 (40 pts): Connection from 'Sample Collection' to 'DNA Extraction'
    if conn_1_2:
        score += 40
        feedback_parts.append("Connection 'Sample Collection' -> 'DNA Extraction' found")
    else:
        feedback_parts.append("Missing connection 'Sample Collection' -> 'DNA Extraction'")

    # Criterion 2 (40 pts): Connection from 'DNA Extraction' to 'PCR Amplification'
    if conn_2_3:
        score += 40
        feedback_parts.append("Connection 'DNA Extraction' -> 'PCR Amplification' found")
    else:
        feedback_parts.append("Missing connection 'DNA Extraction' -> 'PCR Amplification'")

    # Criterion 3 (20 pts): Connection count increased by at least 2
    if current_count >= initial_count + 2:
        score += 20
        feedback_parts.append(f"Connection count increased ({initial_count} -> {current_count})")
    elif current_count > initial_count:
        score += 10
        feedback_parts.append(f"Connection count partially increased ({initial_count} -> {current_count})")
    else:
        feedback_parts.append(f"Connection count unchanged ({initial_count} -> {current_count})")

    # Must have both specific connections to pass
    passed = conn_1_2 and conn_2_3

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts),
        "subscores": {
            "conn_sample_to_dna": conn_1_2,
            "conn_dna_to_pcr": conn_2_3,
            "count_increased": current_count >= initial_count + 2
        }
    }
