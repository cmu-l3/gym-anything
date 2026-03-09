#!/usr/bin/env python3
"""
Verifier for Friendship Symmetry Repair Task.
Verifies that the agent identified asymmetric edges and created mutual connections.
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_friendship_symmetry_repair(traj, env_info, task_info):
    """
    Verify the graph repair task.
    
    Scoring Criteria:
    1. Edge count increased (10 pts)
    2. Specific reverse edges created (20 pts each = 60 pts)
    3. Full symmetry achieved (asymmetry count == 0) (20 pts)
    4. Original edges preserved (10 pts)
    
    Total: 100 pts.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Copy result file
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
            
    score = 0
    feedback_parts = []
    
    initial_count = int(result.get("initial_count", 0))
    current_count = int(result.get("current_count", 0))
    
    # Check 1: Count increased (10 pts)
    if current_count > initial_count:
        score += 10
        feedback_parts.append(f"Edge count increased ({initial_count} -> {current_count})")
    else:
        feedback_parts.append(f"Edge count did not increase (Start: {initial_count}, End: {current_count})")
        
    # Check 2: Specific repairs (60 pts total)
    repairs = [
        ("Maria->John", result.get("has_reverse_maria_john", 0)),
        ("Sophie->David", result.get("has_reverse_sophie_david", 0)),
        ("James->Yuki", result.get("has_reverse_james_yuki", 0))
    ]
    
    repaired_count = 0
    for name, exists in repairs:
        if exists > 0:
            score += 20
            repaired_count += 1
            # feedback_parts.append(f"Created {name}") 
    
    if repaired_count == 3:
        feedback_parts.append("All 3 missing reverse edges created")
    else:
        feedback_parts.append(f"Created {repaired_count}/3 missing reverse edges")

    # Check 3: Full Symmetry (20 pts)
    asymmetry_count = int(result.get("asymmetry_count", 999))
    if asymmetry_count == 0:
        score += 20
        feedback_parts.append("Graph is fully symmetric")
    elif asymmetry_count < 999:
        feedback_parts.append(f"Graph still has {asymmetry_count} asymmetric connections")
        
    # Check 4: Data Preservation (10 pts)
    # Ensure agent didn't just delete everything and start over
    if int(result.get("has_original_edge", 0)) > 0:
        score += 10
    else:
        feedback_parts.append("WARNING: Original edges appear to have been deleted")

    # Final logic
    passed = (score >= 70) and (asymmetry_count == 0)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }