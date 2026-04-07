#!/usr/bin/env python3
"""
Verifier for cleanup_paint_scan_workflow task.
"""

import json
import tempfile
import os
import logging
from typing import Dict, Any

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_cleanup_paint_scan_workflow(traj: Dict[str, Any], env_info: Dict[str, Any], task_info: Dict[str, Any]) -> Dict[str, Any]:
    """
    Verifies that the agent correctly processed the scanned animation:
    1. Imported images
    2. Performed cleanup (Background transparent/removed)
    3. Painted the circle Red
    4. Added a Blue background
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Retrieve result file
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

    # Parse Results
    analysis = result.get("analysis", {})
    file_count = result.get("file_count", 0)
    files_newer = result.get("files_created_during_task", 0)
    
    score = 0
    feedback_parts = []
    
    # Criterion 1: Files Exist & Recent (20 pts)
    if file_count >= 5:
        if files_newer >= 5:
            score += 20
            feedback_parts.append("All frames rendered successfully.")
        else:
            score += 10
            feedback_parts.append("Frames exist but timestamps indicate pre-existing files.")
    elif file_count > 0:
        score += 5
        feedback_parts.append(f"Incomplete render: {file_count}/5 frames.")
    else:
        feedback_parts.append("No output files found.")

    # Criterion 2: Background Color (30 pts)
    # Checks if the background behind the circle is Blue (proving transparency + bg layer)
    # If it's White, they skipped cleanup. If Black/Transparent, they forgot the BG layer.
    if analysis.get("bg_color_match"):
        score += 30
        feedback_parts.append("Background composite successful (Blue).")
    else:
        avg = analysis.get("avg_bg_color", [0,0,0])
        feedback_parts.append(f"Background check failed. Avg Color: {avg}. Expected Blue.")
        if avg[0] > 200 and avg[1] > 200 and avg[2] > 200:
             feedback_parts.append("(Looks like White paper background remains - Cleanup step skipped?)")

    # Criterion 3: Fill Color (30 pts)
    # Checks if the circle is Red.
    if analysis.get("fill_color_match"):
        score += 30
        feedback_parts.append("Painting successful (Red).")
    else:
        avg = analysis.get("avg_fill_color", [0,0,0])
        feedback_parts.append(f"Fill check failed. Avg Color: {avg}. Expected Red.")
        
    # Criterion 4: Line & Motion (20 pts)
    sub_score = 0
    if analysis.get("line_detected"):
        sub_score += 10
        feedback_parts.append("Lines preserved.")
    if analysis.get("motion_detected"):
        sub_score += 10
        feedback_parts.append("Animation motion detected.")
    score += sub_score

    # Final Decision
    # Need at least 70 points (Cleanup + Paint are critical)
    passed = score >= 70
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }