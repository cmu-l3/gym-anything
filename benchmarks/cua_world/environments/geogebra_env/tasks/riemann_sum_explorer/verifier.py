#!/usr/bin/env python3
"""
Verifier for Riemann Sum Interactive Explorer task.
"""

import json
import tempfile
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_riemann_sum_explorer(traj, env_info, task_info):
    """
    Verifies the construction of a Riemann sum applet.
    
    Scoring Criteria (100 pts total):
    1. File creation/validity (15 pts)
    2. Function f(x)=sin(x) definition (20 pts)
    3. Slider creation (20 pts)
    4. UpperSum command usage (15 pts)
    5. LowerSum command usage (15 pts)
    6. Integral/Text annotation (15 pts)
    
    Pass Threshold: 70 pts
    """
    
    # 1. Retrieve result from environment
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Environment copy capability missing."}
    
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load verification results: {str(e)}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)
            
    # 2. Evaluate Logic
    score = 0
    feedback = []
    
    # Criterion 1: File Existence & Anti-gaming (15 pts)
    if result.get("file_found", False):
        if result.get("file_created_during_task", False):
            score += 15
            feedback.append("File 'riemann_sums.ggb' created successfully.")
        else:
            score += 5 # Penalty for using old file
            feedback.append("Warning: File exists but timestamp predates task start (possible stale data).")
    else:
        feedback.append("File 'riemann_sums.ggb' not found in expected directory.")
        return {"passed": False, "score": 0, "feedback": " | ".join(feedback)}

    # Criterion 2: Sine Function (20 pts)
    if result.get("has_sin_function", False):
        score += 20
        feedback.append("Function f(x)=sin(x) found.")
    else:
        feedback.append("Function f(x)=sin(x) NOT found.")

    # Criterion 3: Slider (20 pts)
    if result.get("has_slider", False):
        score += 20
        details = result.get("slider_details", {})
        feedback.append(f"Slider found (label: {details.get('label', '?')}).")
    else:
        feedback.append("No slider control found.")

    # Criterion 4: UpperSum (15 pts)
    if result.get("has_upper_sum", False):
        score += 15
        feedback.append("UpperSum command used.")
    else:
        feedback.append("UpperSum command missing.")

    # Criterion 5: LowerSum (15 pts)
    if result.get("has_lower_sum", False):
        score += 15
        feedback.append("LowerSum command used.")
    else:
        feedback.append("LowerSum command missing.")

    # Criterion 6: Integral or Text Annotation (15 pts)
    # We accept either an Integral command (showing exact value) or a Text element (annotation)
    if result.get("has_integral", False) or result.get("has_text", False):
        score += 15
        feedback.append("Annotation or Integral comparison found.")
    else:
        feedback.append("No text annotation or integral comparison found.")

    # Final Check
    passed = score >= 70
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }