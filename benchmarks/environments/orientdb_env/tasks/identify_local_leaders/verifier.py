#!/usr/bin/env python3
"""
Verifier for identify_local_leaders task.

Scoring Criteria:
1. Schema Update (20 pts): Properties FriendCount and IsLocalLeader exist.
2. Metric Calculation (30 pts): FriendCount values match ground truth.
3. Logic Accuracy (40 pts): IsLocalLeader set correctly for test cases (Star, Chain, Mesh).
4. Export File (10 pts): JSON file exists and contains correct data.
"""

import json
import os
import sys
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_identify_local_leaders(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # 1. Load result JSON
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
    
    # ---------------------------------------------------------
    # CHECK 1: SCHEMA (20 pts)
    # ---------------------------------------------------------
    schema = result.get('schema_snapshot', {})
    classes = schema.get('classes', [])
    profiles_class = next((c for c in classes if c['name'] == 'Profiles'), None)
    
    props = {p['name']: p['type'] for p in profiles_class.get('properties', [])} if profiles_class else {}
    
    has_friend_count = 'FriendCount' in props
    has_leader = 'IsLocalLeader' in props
    
    if has_friend_count and props['FriendCount'] in ['INTEGER', 'LONG', 'SHORT']:
        score += 10
        feedback.append("Schema: FriendCount property created.")
    else:
        feedback.append("Schema: FriendCount property missing or wrong type.")

    if has_leader and props['IsLocalLeader'] == 'BOOLEAN':
        score += 10
        feedback.append("Schema: IsLocalLeader property created.")
    else:
        feedback.append("Schema: IsLocalLeader property missing or wrong type.")

    # ---------------------------------------------------------
    # CHECK 2 & 3: DATA VALUES (70 pts)
    # ---------------------------------------------------------
    # Ground Truth based on topology in setup_task.sh
    # John (3 friends) -> Star Hub -> Leader
    # Maria (0 friends) -> Star Leaf -> Not Leader
    # Luca (1 friend) -> Chain Start -> Not Leader (Friend Anna has 1, 1 not > 1)
    # Anna (1 friend) -> Chain Mid -> Leader (Friend Yuki has 0, 1 > 0)
    # James (1 friend) -> Mesh -> Not Leader (Friend Emma has 1, 1 not > 1)
    
    ground_truth = {
        'john.smith@example.com':   {'count': 3, 'leader': True},
        'maria.garcia@example.com': {'count': 0, 'leader': False},
        'luca.rossi@example.com':   {'count': 1, 'leader': False},
        'anna.mueller@example.com': {'count': 1, 'leader': True},
        'james.brown@example.com':  {'count': 1, 'leader': False}
    }
    
    db_records = result.get('db_state', {}).get('result', [])
    db_map = {r.get('Email'): r for r in db_records}
    
    count_correct = 0
    leader_logic_correct = 0
    total_checks = len(ground_truth)
    
    for email, gt in ground_truth.items():
        rec = db_map.get(email, {})
        
        # Check FriendCount
        actual_count = rec.get('FriendCount')
        if actual_count == gt['count']:
            count_correct += 1
        else:
            feedback.append(f"Metric: Incorrect count for {email}. Expected {gt['count']}, got {actual_count}.")
            
        # Check IsLocalLeader
        actual_leader = rec.get('IsLocalLeader')
        # Allow None to count as False if logic dictates false
        if gt['leader']:
            if actual_leader is True:
                leader_logic_correct += 1
            else:
                feedback.append(f"Logic: {email} should be Leader but is {actual_leader}.")
        else:
            if actual_leader is False or actual_leader is None:
                leader_logic_correct += 1
            else:
                feedback.append(f"Logic: {email} should NOT be Leader but is {actual_leader}.")

    # Score calculation
    # 30 pts for counts
    score += int((count_correct / total_checks) * 30)
    
    # 40 pts for leader logic
    score += int((leader_logic_correct / total_checks) * 40)

    # ---------------------------------------------------------
    # CHECK 4: EXPORT FILE (10 pts)
    # ---------------------------------------------------------
    output_exists = result.get('output_exists', False)
    file_created = result.get('file_created_during_task', False)
    
    if output_exists and file_created:
        # Load the file content to verify
        try:
            temp_output = tempfile.NamedTemporaryFile(delete=False)
            copy_from_env(result['output_file_path'], temp_output.name)
            with open(temp_output.name, 'r') as f:
                output_data = json.load(f)
            os.unlink(temp_output.name)
            
            if isinstance(output_data, list) and len(output_data) > 0:
                # Check if John and Anna are in the list
                names = [p.get('Name') for p in output_data]
                if "John" in names and "Anna" in names:
                    score += 10
                    feedback.append("Export: JSON file valid and contains leaders.")
                else:
                    score += 5
                    feedback.append("Export: JSON file exists but missing expected leaders.")
            else:
                feedback.append("Export: JSON file format incorrect.")
        except Exception as e:
            feedback.append(f"Export: Failed to verify file content: {e}")
    elif output_exists:
        score += 5
        feedback.append("Export: File exists but was not created during task window.")
    else:
        feedback.append("Export: Output file not found.")

    passed = score >= 70
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }