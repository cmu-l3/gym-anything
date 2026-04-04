#!/usr/bin/env python3
"""Verifier for export_protocol_hierarchy task."""

import json
import tempfile
import os


def verify_export_protocol_hierarchy(traj, env_info, task_info):
    """Verify that the user exported the protocol hierarchy statistics."""

    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Copy result file from container
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

    feedback_parts = []
    score = 0

    ground_truth = result.get('ground_truth', {})

    # Criterion 1: Output file exists (20 pts)
    if result.get('output_file_exists'):
        score += 20
        feedback_parts.append("Protocol hierarchy file created")
    else:
        feedback_parts.append("Protocol hierarchy file not found")
        return {"passed": False, "score": 0, "feedback": " | ".join(feedback_parts)}

    # Criterion 2: File has meaningful content (10 pts)
    content_length = result.get('content_length', 0)
    if content_length > 50:
        score += 10
        feedback_parts.append(f"File has substantial content ({content_length} chars)")
    elif content_length > 0:
        score += 5
        feedback_parts.append(f"File has minimal content ({content_length} chars)")
    else:
        feedback_parts.append("File is empty")

    # Criterion 3: Mentions Ethernet layer (15 pts)
    if result.get('mentions_ethernet'):
        score += 15
        feedback_parts.append("Contains Ethernet protocol")
    else:
        feedback_parts.append("Missing Ethernet protocol")

    # Criterion 4: Mentions IP layer (15 pts)
    if result.get('mentions_ip'):
        score += 15
        feedback_parts.append("Contains IP protocol")
    else:
        feedback_parts.append("Missing IP protocol")

    # Criterion 5: Mentions TCP layer (15 pts)
    if result.get('mentions_tcp'):
        score += 15
        feedback_parts.append("Contains TCP protocol")
    else:
        feedback_parts.append("Missing TCP protocol")

    # Criterion 6: Mentions HTTP (15 pts)
    if result.get('mentions_http'):
        score += 15
        feedback_parts.append("Contains HTTP protocol")
    else:
        feedback_parts.append("Missing HTTP protocol")

    # Criterion 7: Contains percentage or numerical data (10 pts)
    if result.get('has_percentages'):
        score += 10
        feedback_parts.append("Contains statistical data (percentages/counts)")
    else:
        feedback_parts.append("Missing statistical data")

    passed = score >= 70
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }
