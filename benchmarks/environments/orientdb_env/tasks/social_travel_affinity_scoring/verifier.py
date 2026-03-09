#!/usr/bin/env python3
"""
Verifier for social_travel_affinity_scoring task.
"""

import json
import base64
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_social_travel_affinity_scoring(traj, env_info, task_info):
    """
    Verifies the social travel affinity scoring task.
    Criteria:
    1. HasVisited edges must exist (derived from Stays).
    2. AffinityScore property must exist on HasFriend.
    3. AffinityScore must be calculated correctly for test users (Jaccard).
    4. Output file must exist and contain reasonable data.
    """
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

    score = 0
    feedback_parts = []
    
    db_state = result.get('db_state', {})
    
    # Criterion 1: HasVisited Edges Created (30 pts)
    # We expect some edges. The seed data + test data guarantees at least 4 (2 for Alice, 2 for Bob) + others in DemoDB.
    edge_count = db_state.get('has_visited_edge_count', 0)
    if edge_count >= 4:
        score += 30
        feedback_parts.append(f"HasVisited edges created ({edge_count})")
    elif edge_count > 0:
        score += 15
        feedback_parts.append(f"Some HasVisited edges created ({edge_count}), but fewer than expected")
    else:
        feedback_parts.append("No HasVisited edges found")

    # Criterion 2: Property Definition (10 pts)
    if db_state.get('affinity_score_property_exists', False):
        score += 10
        feedback_parts.append("AffinityScore property exists")
    else:
        feedback_parts.append("AffinityScore property missing")

    # Criterion 3: Score Calculation Accuracy (40 pts)
    # Alice (Italy, France) vs Bob (Italy, Germany) -> Jaccard = 1/3 = 0.3333...
    test_score = db_state.get('test_affinity_score', -1)
    # Bob (Italy, Germany) vs Charlie (None) -> Jaccard = 0
    zero_score = db_state.get('test_zero_score', -1)
    
    # Check Alice-Bob score
    if test_score != -1:
        if 0.30 <= test_score <= 0.36:
            score += 25
            feedback_parts.append(f"Test Score correct ({test_score:.4f})")
        else:
            feedback_parts.append(f"Test Score incorrect (got {test_score}, expected ~0.33)")
    else:
        feedback_parts.append("Test Score not found (edge missing or property not set)")

    # Check Bob-Charlie score (should be 0)
    if zero_score != -1:
        if 0 <= zero_score <= 0.01:
            score += 15
            feedback_parts.append(f"Zero Score correct ({zero_score})")
        else:
            feedback_parts.append(f"Zero Score incorrect (got {zero_score}, expected 0)")
    
    # Criterion 4: Report Generation (20 pts)
    output_exists = result.get('output_file_exists', False)
    output_created = result.get('output_file_created_during_task', False)
    content_b64 = result.get('output_content_base64', "")
    
    if output_exists and output_created:
        score += 10
        feedback_parts.append("Report file created")
        
        # Check content format
        try:
            content = base64.b64decode(content_b64).decode('utf-8')
            if len(content.strip()) > 0 and ":" in content:
                score += 10
                feedback_parts.append("Report content format looks valid")
            else:
                feedback_parts.append("Report content empty or invalid format")
        except:
            feedback_parts.append("Could not parse report content")
    else:
        feedback_parts.append("Report file missing or stale")

    passed = score >= 70
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }