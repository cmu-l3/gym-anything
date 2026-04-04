#!/usr/bin/env python3
"""
Verifier for macro_workflow_automation task.
"""

import json
import os
import tempfile
import re
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_macro_workflow(traj, env_info, task_info):
    """
    Verify the generated ImageJ macro.
    
    Criteria:
    1. File creation (10 pts) - must be created during task
    2. Static Analysis (60 pts):
       - Contains Gaussian Blur with sigma ~ 2 (20 pts)
       - Contains Threshold (Otsu/Auto) (20 pts)
       - Contains Analyze Particles with size constraint (20 pts)
    3. Functional Test (30 pts):
       - Macro runs successfully on a fresh image and produces results
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load results
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result: {e}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    score = 0
    feedback = []
    
    # 1. File Existence & Timestamp (10 pts)
    file_exists = result.get("file_exists", False)
    task_start = result.get("task_start", 0)
    file_mtime = result.get("file_mtime", 0)
    
    if file_exists:
        if file_mtime > task_start:
            score += 10
            feedback.append("Macro file created successfully.")
        else:
            feedback.append("Warning: Macro file timestamp predates task start.")
    else:
        return {"passed": False, "score": 0, "feedback": "Macro file not found at expected location."}

    # 2. Static Analysis (60 pts)
    content = result.get("macro_content", "")
    
    # Check for Gaussian Blur (sigma=2)
    # Regex handles variations like "sigma=2", "sigma=2.00", "sigma = 2"
    if re.search(r'run\("Gaussian Blur\.\.\.",.*sigma\s*=\s*2', content, re.IGNORECASE):
        score += 20
        feedback.append("Gaussian Blur command found with correct sigma.")
    elif "Gaussian Blur" in content:
        score += 10
        feedback.append("Gaussian Blur found but parameters check failed (expected sigma=2).")
    else:
        feedback.append("Missing Gaussian Blur command.")

    # Check for Thresholding
    # Look for "setAutoThreshold" (recorder output) or "run('Threshold')"
    if "setAutoThreshold" in content or "setThreshold" in content or "Threshold" in content:
        # Check for Otsu specifically
        if "Otsu" in content:
            score += 20
            feedback.append("Otsu Thresholding found.")
        else:
            score += 10
            feedback.append("Thresholding found, but method not explicitly 'Otsu' in script.")
    else:
        feedback.append("Missing Threshold command.")

    # Check for Analyze Particles
    # Look for size=20 or size=20-Infinity
    if re.search(r'run\("Analyze Particles\.\.\.",.*size\s*=\s*20', content, re.IGNORECASE):
        score += 20
        feedback.append("Analyze Particles found with correct size filter.")
    elif "Analyze Particles" in content:
        score += 10
        feedback.append("Analyze Particles found but size parameter check failed (expected size=20...).")
    else:
        feedback.append("Missing Analyze Particles command.")

    # 3. Functional Test (30 pts)
    func_test = result.get("functional_test", {})
    if func_test.get("success", False):
        count = func_test.get("particle_count", 0)
        # Expected range for Blobs with Sigma=2, Otsu, Size>20 is approx 40-70
        if 40 <= count <= 80:
            score += 30
            feedback.append(f"Functional test passed: Generated {count} particles (within expected range).")
        else:
            score += 15
            feedback.append(f"Functional test ran but produced unexpected particle count: {count} (expected 40-80).")
    else:
        feedback.append("Functional test failed: Macro could not be executed on a fresh image.")

    passed = score >= 70
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }