#!/usr/bin/env python3
import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_fix_recommender_system(traj, env_info, task_info):
    """
    Verify the fix_recommender_system task.
    
    Scoring:
    - Bug 1 (Similarity Logic): 30 pts
    - Bug 2 (Neighbor Selection Logic): 30 pts
    - Bug 3 (Prediction Logic): 30 pts
    - All Visible Tests Pass: 10 pts
    
    The 'logic' checks come from a hidden verification script run inside the container,
    which tests the functions with specific inputs known to differentiate the buggy
    vs fixed implementation.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Copy result file
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/recommender_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {
            "passed": False, 
            "score": 0, 
            "feedback": f"Failed to read result file: {str(e)}. Did the export script run?"
        }
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)
            
    score = 0
    feedback_parts = []
    
    # Check Bug 1: Cosine Similarity
    if result.get("bug1_logic_correct"):
        score += 30
        feedback_parts.append("Bug 1 (Similarity): Fixed (Correct Euclidean norm denominator)")
    else:
        feedback_parts.append("Bug 1 (Similarity): FAILED (Likely still using sum instead of sqrt(sum^2))")
        
    # Check Bug 2: Neighbor Selection
    if result.get("bug2_logic_correct"):
        score += 30
        feedback_parts.append("Bug 2 (Selection): Fixed (Correctly selects highest similarity neighbors)")
    else:
        feedback_parts.append("Bug 2 (Selection): FAILED (Likely selecting lowest similarity due to argsort order)")
        
    # Check Bug 3: Prediction
    if result.get("bug3_logic_correct"):
        score += 30
        feedback_parts.append("Bug 3 (Prediction): Fixed (Correctly normalizes by sum of weights)")
    else:
        feedback_parts.append("Bug 3 (Prediction): FAILED (Likely still dividing by count)")
        
    # Check Visible Tests
    if result.get("visible_tests_passed"):
        score += 10
        feedback_parts.append("Regression Tests: All Passed")
    else:
        passed_count = result.get("tests_passed_count", 0)
        feedback_parts.append(f"Regression Tests: Failed ({passed_count} passed)")
        
    passed = (score >= 90)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": "\n".join(feedback_parts)
    }