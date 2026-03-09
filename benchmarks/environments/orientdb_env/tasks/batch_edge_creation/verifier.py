#!/usr/bin/env python3
"""
Verifier for batch_edge_creation task in OrientDB.
"""

import json
import tempfile
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_batch_edge_creation(traj, env_info, task_info):
    """
    Verify that the IsNearby edge class was created and populated correctly.
    
    Scoring Criteria:
    1. Class 'IsNearby' exists (20 pts)
    2. Class extends 'E' (10 pts)
    3. Property 'Type' exists (10 pts)
    4. Edge count matches expected calculation (20 pts)
    5. Edges have correct Type='same_city' value (20 pts)
    6. Edges are valid (connect same cities) (20 pts)
       - Deducts points for invalid directions or mismatched cities
    """
    
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Copy result JSON from container
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    score = 0
    feedback = []
    
    # 1. Class Exists (20 pts)
    if result.get("class_exists", False):
        score += 20
        feedback.append("Class 'IsNearby' created.")
    else:
        feedback.append("Class 'IsNearby' NOT found.")
        # Critical failure, return early
        return {"passed": False, "score": 0, "feedback": " | ".join(feedback)}

    # 2. Inheritance (10 pts)
    super_class = result.get("super_class", "")
    if super_class == "E":
        score += 10
        feedback.append("Correctly extends class 'E'.")
    else:
        feedback.append(f"Incorrect superclass: '{super_class}' (expected 'E').")

    # 3. Property Definition (10 pts)
    if result.get("has_type_property", False):
        score += 10
        feedback.append("Property 'Type' defined.")
    else:
        feedback.append("Property 'Type' NOT defined in schema.")
        # We might still give partial credit if data has the property, 
        # but verification checks strict schema creation as per prompt "Add a String property".

    # 4. Edge Volume (20 pts)
    total_edges = result.get("total_edges", 0)
    expected_edges = result.get("expected_edges", 0)
    
    if total_edges == 0:
        feedback.append("No edges were created.")
    elif total_edges == expected_edges:
        score += 20
        feedback.append(f"Correct number of edges created ({total_edges}).")
    elif total_edges > 0:
        # Partial credit for creating edges, but wrong count
        # Could happen if they ran it twice without checking uniqueness, or logic error
        diff = abs(total_edges - expected_edges)
        pct_error = diff / max(1, expected_edges)
        if pct_error < 0.1: # Close enough
            score += 15
            feedback.append(f"Edge count close to expected ({total_edges}/{expected_edges}).")
        else:
            score += 5
            feedback.append(f"Edge count mismatch: {total_edges} (expected {expected_edges}).")

    # 5. Property Value (20 pts)
    correct_type_count = result.get("correct_type_count", 0)
    if correct_type_count == total_edges and total_edges > 0:
        score += 20
        feedback.append("All edges have correct Type='same_city'.")
    elif correct_type_count > 0:
        pct = correct_type_count / max(1, total_edges)
        points = int(20 * pct)
        score += points
        feedback.append(f"Only {correct_type_count}/{total_edges} edges have correct Type.")

    # 6. Validity / Logic (20 pts)
    # Check for invalid edges (wrong cities or wrong directions)
    invalid_city = result.get("invalid_city_match", 0)
    invalid_direction = result.get("invalid_direction", 0)
    
    validity_score = 20
    if invalid_city > 0:
        validity_score -= 10
        feedback.append(f"Found {invalid_city} edges connecting mismatched cities.")
    
    if invalid_direction > 0:
        validity_score -= 10
        feedback.append(f"Found {invalid_direction} edges with wrong direction/classes (must be Hotel->Restaurant).")
        
    if total_edges == 0:
        validity_score = 0
        
    score += max(0, validity_score)

    passed = score >= 70
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }