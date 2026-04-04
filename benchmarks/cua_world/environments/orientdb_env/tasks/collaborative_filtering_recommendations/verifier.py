#!/usr/bin/env python3
"""
Verifier for collaborative_filtering_recommendations task.
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_collaborative_filtering(traj, env_info, task_info):
    """
    Verify the collaborative filtering recommendation engine implementation.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_restaurants = set(metadata.get('expected_restaurants', []))
    excluded_restaurants = set(metadata.get('excluded_restaurants', []))
    
    # Load result JSON
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
    
    # 1. Schema Verification (15 pts)
    schema = result.get('schema', {})
    if schema.get('Recommendations') == "true":
        score += 10
        feedback_parts.append("Vertex class 'Recommendations' created.")
    else:
        feedback_parts.append("Vertex class 'Recommendations' missing.")
        
    if schema.get('HasRecommendation') == "true":
        score += 5
        feedback_parts.append("Edge class 'HasRecommendation' created.")
    else:
        feedback_parts.append("Edge class 'HasRecommendation' missing.")

    # 2. Data Verification
    data = result.get('data', {})
    recs = data.get('recommendations', [])
    rec_count = data.get('rec_count', 0)
    edge_count = data.get('edge_count', 0)
    
    # Check Count (15 pts)
    if rec_count == 4:
        score += 15
        feedback_parts.append("Correct number of recommendations (4).")
    else:
        feedback_parts.append(f"Incorrect recommendation count: {rec_count} (expected 4).")

    # Check Content (40 pts)
    found_restaurants = set()
    found_scores = {}
    
    for r in recs:
        name = r.get('RestaurantName')
        if name:
            found_restaurants.add(name)
            found_scores[name] = r.get('Score')

    # Points for correct inclusions
    correct_found = 0
    for expected in expected_restaurants:
        if expected in found_restaurants:
            score += 10
            correct_found += 1
            feedback_parts.append(f"Found {expected}.")
        else:
            feedback_parts.append(f"Missing {expected}.")

    # Points for correct exclusions (10 pts)
    exclusion_failed = False
    for excluded in excluded_restaurants:
        if excluded in found_restaurants:
            exclusion_failed = True
            feedback_parts.append(f"Failed to exclude {excluded} (already visited).")
    
    if not exclusion_failed and correct_found > 0:
        score += 10
        feedback_parts.append("Correctly excluded visited restaurants.")

    # Check Scores (5 pts)
    # All scores should be 1 for this dataset
    scores_correct = True
    for s in found_scores.values():
        if s != 1:
            scores_correct = False
    
    if scores_correct and len(found_scores) > 0:
        score += 5
        feedback_parts.append("Scores calculated correctly.")
    elif len(found_scores) > 0:
        feedback_parts.append("Some scores were incorrect.")

    # Check Edges (10 pts)
    if edge_count >= 4:
        score += 10
        feedback_parts.append(f"Edges created correctly ({edge_count}).")
    elif edge_count > 0:
        score += 5
        feedback_parts.append(f"Some edges created ({edge_count}), but fewer than recommendations.")
    else:
        feedback_parts.append("No 'HasRecommendation' edges found linking to Profile.")

    # 3. File Verification (5 pts)
    if result.get('query_file_exists') and result.get('query_file_size', 0) > 20:
        score += 5
        feedback_parts.append("Query file saved.")
    else:
        feedback_parts.append("Query file missing or empty.")

    # Final Pass Check
    # Must have schema, reasonable data, and at least 3 correct restaurants
    passed = (schema.get('Recommendations') == "true" and 
              rec_count == 4 and 
              correct_found >= 3 and
              score >= 70)

    return {
        "passed": passed,
        "score": min(score, 100),
        "feedback": " ".join(feedback_parts)
    }