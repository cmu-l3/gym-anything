#!/usr/bin/env python3
import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_fix_astro_coordinates(traj, env_info, task_info):
    """
    Verify the fix_astro_coordinates task.
    
    Scoring:
    - Bug 1 Fixed (Galactic coords): 25 pts
    - Bug 2 Fixed (Azimuth atan2): 25 pts
    - Bug 3 Fixed (Separation formula): 25 pts
    - Bug 4 Fixed (HMS parsing): 15 pts
    - No Regressions: 10 pts
    
    Total: 100 pts
    Threshold: 65 pts
    """
    copy_from_env = env_info.get("copy_from_env")
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Verification failed: copy_from_env unavailable"}
    
    result_path = "/tmp/fix_astro_coordinates_result.json"
    
    try:
        with tempfile.NamedTemporaryFile(delete=False, suffix=".json") as tmp:
            tmp_path = tmp.name
        
        try:
            copy_from_env(result_path, tmp_path)
            with open(tmp_path, "r") as f:
                result = json.load(f)
        finally:
            if os.path.exists(tmp_path):
                os.unlink(tmp_path)
                
    except Exception as e:
        return {
            "passed": False, 
            "score": 0, 
            "feedback": f"Failed to retrieve/parse verification result: {str(e)}"
        }
    
    score = 0
    feedback = []
    
    # Bug 1: Galactic Coords (25 pts)
    if result.get("bug1_fixed"):
        score += 25
        feedback.append("Bug 1 (Galactic NGP conversion) fixed.")
    else:
        feedback.append("Bug 1 NOT fixed: Galactic coordinate transform still incorrect.")
        
    # Bug 2: Azimuth atan2 (25 pts)
    if result.get("bug2_fixed"):
        score += 25
        feedback.append("Bug 2 (Azimuth atan2 arguments) fixed.")
    else:
        feedback.append("Bug 2 NOT fixed: Horizontal azimuth calculation incorrect.")
        
    # Bug 3: Angular Separation (25 pts)
    if result.get("bug3_fixed"):
        score += 25
        feedback.append("Bug 3 (Separation cosine term) fixed.")
    else:
        feedback.append("Bug 3 NOT fixed: Angular separation formula incorrect.")
        
    # Bug 4: HMS Parsing (15 pts)
    if result.get("bug4_fixed"):
        score += 15
        feedback.append("Bug 4 (HMS seconds parsing) fixed.")
    else:
        feedback.append("Bug 4 NOT fixed: HMS to degrees conversion incorrect.")
        
    # No Regression (10 pts)
    if result.get("no_regression") and result.get("all_tests_pass"):
        score += 10
        feedback.append("All tests passed with no regressions.")
    elif result.get("no_regression"):
        # Regressions passed but not all tests passed (partial fix state)
        # Give partial points
        score += 5
        feedback.append("Existing tests pass, but some fixes missing.")
    else:
        feedback.append("Regression detected: Previously passing tests are failing.")
        
    passed = score >= 65
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback),
        "details": result
    }