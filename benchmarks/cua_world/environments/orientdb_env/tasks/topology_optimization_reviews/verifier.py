#!/usr/bin/env python3
"""
Verifier for topology_optimization_reviews task.

Verifies:
1. Schema Refactoring: 'PostedReview' edge class created with correct properties.
2. Data Migration: Edges count matches original vertices count.
3. Data Integrity: Specific review data (Rating, Comment) preserved.
4. Cleanup: Old classes/vertices deleted.
"""

import json
import tempfile
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_topology_optimization(traj, env_info, task_info):
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
        return {"passed": False, "score": 0, "feedback": f"Failed to load result JSON: {str(e)}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback_parts = []
    
    # Extract data
    schema_info = result.get('schema', {})
    counts = result.get('counts', {})
    spot_check = result.get('spot_check', {})

    # Criterion 1: Schema Creation (20 points)
    if schema_info.get('PostedReview_exists'):
        score += 10
        feedback_parts.append("PostedReview class created")
        
        props = schema_info.get('properties', [])
        required = ['Rating', 'Comment', 'ReviewDate']
        missing = [p for p in required if p not in props]
        
        if not missing:
            score += 10
            feedback_parts.append("Properties correct")
        else:
            feedback_parts.append(f"Missing properties: {missing}")
    else:
        feedback_parts.append("PostedReview class NOT found")
        return {"passed": False, "score": 0, "feedback": " | ".join(feedback_parts)}

    # Criterion 2: Data Migration Count (30 points)
    initial_cnt = counts.get('initial_reviews', 0)
    final_edges = counts.get('final_edges', 0)
    
    if final_edges >= initial_cnt and final_edges > 0:
        score += 30
        feedback_parts.append(f"Migration successful ({final_edges} edges created)")
    elif final_edges > 0:
        score += 15
        feedback_parts.append(f"Partial migration ({final_edges}/{initial_cnt} edges)")
    else:
        feedback_parts.append("No edges migrated")

    # Criterion 3: Data Integrity Spot Check (30 points)
    # Expected: Rating=4, Comment starts with "Great location"
    if spot_check:
        rating = spot_check.get('Rating')
        comment = spot_check.get('Comment', '')
        
        if rating == 4 and "Great location" in comment:
            score += 30
            feedback_parts.append("Data integrity verified (Spot check passed)")
        else:
            score += 10
            feedback_parts.append(f"Spot check mismatch: Found Rating={rating}, Comment='{comment}'")
    else:
        feedback_parts.append("Spot check failed: specific review not found")

    # Criterion 4: Cleanup (20 points)
    # Reviews vertex count should be 0 (either class deleted or records deleted)
    old_remaining = counts.get('remaining_old_vertices', 0)
    reviews_class_exists = schema_info.get('Reviews_class_exists', False)
    
    if not reviews_class_exists:
        score += 10
        feedback_parts.append("Reviews class deleted")
    elif old_remaining == 0:
        score += 5
        feedback_parts.append("Reviews vertices deleted (class remains)")
    else:
        feedback_parts.append(f"Cleanup incomplete: {old_remaining} Reviews vertices remain")
        
    if not schema_info.get('MadeReview_class_exists') and not schema_info.get('HasReview_class_exists'):
        score += 10
        feedback_parts.append("Old edge classes deleted")
    else:
        feedback_parts.append("Old edge classes still exist")

    # Final Verification
    passed = score >= 70
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }