#!/usr/bin/env python3
"""Verifier for count_dns_queries task."""

import json
import tempfile
import os


def verify_count_dns_queries(traj, env_info, task_info):
    """Verify that the user correctly counted DNS queries."""

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

    ground_truth = result.get('ground_truth_dns_queries', 0)

    # Criterion 1: Output file exists (30 pts)
    if result.get('output_file_exists'):
        score += 30
        feedback_parts.append("Output file created")
    else:
        feedback_parts.append("Output file not found at expected location")
        return {"passed": False, "score": 0, "feedback": " | ".join(feedback_parts)}

    # Criterion 2: User answer is a valid number (20 pts)
    user_answer_str = result.get('user_answer', '').strip()
    try:
        user_answer = int(user_answer_str)
        score += 20
        feedback_parts.append(f"Valid number provided: {user_answer}")
    except (ValueError, TypeError):
        feedback_parts.append(f"Invalid answer format: '{user_answer_str}' (expected integer)")
        return {"passed": False, "score": score, "feedback": " | ".join(feedback_parts)}

    # Criterion 3: Answer matches ground truth exactly (50 pts)
    if user_answer == ground_truth:
        score += 50
        feedback_parts.append(f"Exact match: {user_answer} DNS queries (ground truth: {ground_truth})")
    elif abs(user_answer - ground_truth) <= 2:
        # Allow small tolerance (off by 1-2 due to display quirks)
        score += 30
        feedback_parts.append(f"Close match: {user_answer} vs {ground_truth} expected (within tolerance)")
    else:
        feedback_parts.append(f"Count mismatch: {user_answer} vs {ground_truth} expected")

    passed = score >= 70
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }
