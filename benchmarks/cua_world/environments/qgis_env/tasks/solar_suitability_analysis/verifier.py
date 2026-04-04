#!/usr/bin/env python3
"""
Verifier for solar_suitability_analysis task.

Evaluates the agent's binary raster output against ground truth calculated from the input DEM.
"""

import json
import tempfile
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_solar_suitability(traj, env_info, task_info):
    """
    Verify the solar suitability raster analysis.
    
    Scoring Criteria:
    1. Output file exists and is a valid raster (15 pts)
    2. File created during task execution (10 pts)
    3. Spatial dimensions match input DEM (15 pts)
    4. Result contains data (not empty/all zero) (10 pts)
    5. Logic Verification - Slope: Identified areas actually have low slope (25 pts)
    6. Logic Verification - Aspect: Identified areas actually face south (25 pts)
    
    Pass Threshold: 70 points
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
    
    # 1. File Existence & Validity (15 pts)
    file_exists = result.get("file_exists", False)
    analysis = result.get("analysis", {})
    valid_format = analysis.get("valid_format", False)
    
    if file_exists and valid_format:
        score += 15
        feedback_parts.append("Valid output file found")
    elif file_exists:
        score += 5
        feedback_parts.append("Output file exists but format invalid")
    else:
        feedback_parts.append("No output file found")
        return {"passed": False, "score": 0, "feedback": " | ".join(feedback_parts)}
        
    # 2. Created During Task (10 pts)
    if result.get("created_during_task", False):
        score += 10
        feedback_parts.append("File created during task")
    else:
        feedback_parts.append("File timestamp pre-dates task start")

    # 3. Spatial Alignment (15 pts)
    if analysis.get("spatial_match", False):
        score += 15
        feedback_parts.append("Spatial extent matches input")
    else:
        feedback_parts.append("Spatial extent mismatch (reprojection or extent error)")

    # 4. Content Check (10 pts)
    if analysis.get("has_content", False):
        score += 10
        feedback_parts.append("Result contains identified areas")
    else:
        feedback_parts.append("Result is empty (no suitable areas found)")
        # If the result is empty, logic checks will fail (0 score), so we stop here generally 
        # unless ground truth implies it SHOULD be empty. 
        # Our synthetic data ensures there are suitable areas.
        
    # 5. Logic Verification - Slope (25 pts)
    # valid_slope_pct is the % of agent-selected pixels that actually have slope < 12 deg
    slope_score = analysis.get("valid_slope_pct", 0.0)
    slope_pts = int(slope_score * 25)
    score += slope_pts
    if slope_score > 0.8:
        feedback_parts.append(f"Slope criteria met ({slope_score:.0%})")
    else:
        feedback_parts.append(f"Slope criteria failed ({slope_score:.0%})")

    # 6. Logic Verification - Aspect (25 pts)
    # valid_aspect_pct is the % of agent-selected pixels that actually have aspect 130-230 deg
    aspect_score = analysis.get("valid_aspect_pct", 0.0)
    aspect_pts = int(aspect_score * 25)
    score += aspect_pts
    if aspect_score > 0.8:
        feedback_parts.append(f"Aspect criteria met ({aspect_score:.0%})")
    else:
        feedback_parts.append(f"Aspect criteria failed ({aspect_score:.0%})")

    # Calculate final status
    passed = score >= 70
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts),
        "details": {
            "iou": analysis.get("iou", 0),
            "accuracy": analysis.get("accuracy", 0),
            "pixel_count": analysis.get("pixel_count", 0)
        }
    }