#!/usr/bin/env python3
"""
Verifier for link_incidents_to_problem task.

Verifies that:
1. The 3 target VPN requests are linked to the Problem.
2. The 2 distractor requests (Printer, SAP) are NOT linked.
"""

import json
import logging
import os
import tempfile

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_link_incidents_to_problem(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load result from container
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

    # Extract Data
    associated_reqs = set(str(x) for x in result.get("associated_requests", []))
    target_ids = set(str(x) for x in result.get("target_ids", []))
    distractor_ids = set(str(x) for x in result.get("distractor_ids", []))
    
    problem_id = result.get("problem_id")
    if not problem_id:
        return {"passed": False, "score": 0, "feedback": "Setup failed: No Problem ID found."}

    # Scoring Logic
    score = 0
    feedback = []

    # 1. Check Targets (75 points total, 25 each)
    correct_links = 0
    for tid in target_ids:
        if tid in associated_reqs:
            correct_links += 1
            score += 25
        else:
            feedback.append(f"Missing link for VPN request ID {tid}")
    
    if correct_links == len(target_ids):
        feedback.append("All VPN requests correctly linked.")

    # 2. Check Distractors (25 points total, -12.5 penalty each)
    distractor_score = 25
    distractors_linked = 0
    for did in distractor_ids:
        if did in associated_reqs:
            distractors_linked += 1
            distractor_score -= 12.5
            feedback.append(f"Incorrectly linked unrelated request ID {did}")
    
    if distractors_linked == 0:
        feedback.append("No unrelated requests linked.")
    
    score += max(0, distractor_score)

    # 3. Final calculation
    # Max score = 75 (targets) + 25 (distractors) = 100
    
    passed = (correct_links >= 2) and (distractors_linked == 0) and (score >= 75)
    
    return {
        "passed": passed,
        "score": int(score),
        "feedback": " ".join(feedback),
        "details": {
            "associated": list(associated_reqs),
            "targets": list(target_ids),
            "correct_count": correct_links,
            "incorrect_count": distractors_linked
        }
    }