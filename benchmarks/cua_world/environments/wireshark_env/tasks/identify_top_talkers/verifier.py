#!/usr/bin/env python3
"""Verifier for identify_top_talkers task."""

import json
import tempfile
import os


def verify_identify_top_talkers(traj, env_info, task_info):
    """Verify that the user correctly identified the top talker IP."""

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

    ground_truth = result.get('ground_truth_top_talker', '').strip()
    user_answer = result.get('user_answer', '').strip()

    # Criterion 1: Output file exists (25 pts)
    if result.get('output_file_exists'):
        score += 25
        feedback_parts.append("Output file created")
    else:
        feedback_parts.append("Output file not found")
        return {"passed": False, "score": 0, "feedback": " | ".join(feedback_parts)}

    # Criterion 2: Answer is a valid IP address format (15 pts)
    parts = user_answer.split('.')
    is_valid_ip = len(parts) == 4 and all(p.isdigit() and 0 <= int(p) <= 255 for p in parts)
    if is_valid_ip:
        score += 15
        feedback_parts.append(f"Valid IP address: {user_answer}")
    else:
        feedback_parts.append(f"Invalid IP format: '{user_answer}'")
        return {"passed": False, "score": score, "feedback": " | ".join(feedback_parts)}

    # Criterion 3: Answer matches ground truth exactly (60 pts)
    if user_answer == ground_truth:
        score += 60
        feedback_parts.append(f"Exact match: {user_answer} is the top sender")
    else:
        # Partial credit: check if the user identified a top-3 sender
        user_rank_str = result.get('user_rank', '')
        if user_rank_str:
            try:
                user_rank = int(user_rank_str)
                if user_rank <= 3:
                    score += 30
                    feedback_parts.append(f"Partial match: {user_answer} is ranked #{user_rank} (top is {ground_truth})")
                elif user_rank <= 5:
                    score += 15
                    feedback_parts.append(f"Close: {user_answer} is ranked #{user_rank} (top is {ground_truth})")
                else:
                    feedback_parts.append(f"Wrong: {user_answer} is ranked #{user_rank} (top is {ground_truth})")
            except ValueError:
                feedback_parts.append(f"Mismatch: {user_answer} vs expected {ground_truth}")
        else:
            feedback_parts.append(f"Mismatch: {user_answer} vs expected {ground_truth}")

    passed = score >= 70
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }
