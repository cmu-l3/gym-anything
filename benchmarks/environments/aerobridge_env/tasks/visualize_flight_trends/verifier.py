#!/usr/bin/env python3
"""
Verifier for visualize_flight_trends task.
Checks if the agent successfully installed matplotlib, queried the database,
and generated a valid chart image.
"""

import json
import os
import base64
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_visualize_flight_trends(traj, env_info, task_info):
    """
    Verify the flight trends visualization task.
    
    Criteria:
    1. 'matplotlib' library installed (20 pts)
    2. Script '/home/ga/generate_chart.py' exists and attempts to use FlightPlan (30 pts)
    3. Output image '/home/ga/flight_activity.png' exists (25 pts)
    4. Output image is valid size (>5KB) and created during task (25 pts)
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Retrieve result JSON
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
    
    # 1. Environment Setup (20 pts)
    if result.get('matplotlib_installed', False):
        score += 20
        feedback_parts.append("Matplotlib installed successfully (+20)")
    else:
        feedback_parts.append("Matplotlib not found in pip freeze")

    # 2. Script Analysis (30 pts)
    if result.get('script_exists', False):
        script_score = 10
        feedback_parts.append("Script file created (+10)")
        
        if result.get('script_imports_flightplan', False):
            script_score += 10
            feedback_parts.append("Script references FlightPlan model (+10)")
        else:
            feedback_parts.append("Script does not appear to reference FlightPlan model")
            
        if result.get('script_imports_matplotlib', False):
            script_score += 10
            feedback_parts.append("Script imports matplotlib (+10)")
            
        score += script_score
    else:
        feedback_parts.append("Generation script not found")

    # 3. Output Image Existence (25 pts)
    if result.get('image_exists', False):
        score += 25
        feedback_parts.append("Output image generated (+25)")
    else:
        feedback_parts.append("Output image not found")

    # 4. Output Image Validity (25 pts)
    validity_score = 0
    if result.get('image_created_during_task', False):
        validity_score += 15
        feedback_parts.append("Image created during task session (+15)")
    else:
        feedback_parts.append("Image timestamp invalid (pre-dates task?)")
        
    size = result.get('image_size_bytes', 0)
    if size > 5000:
        validity_score += 10
        feedback_parts.append(f"Image size valid ({size} bytes) (+10)")
    elif size > 0:
        feedback_parts.append(f"Image too small ({size} bytes) - likely empty/corrupt")
    
    score += validity_score

    passed = score >= 70
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }