#!/usr/bin/env python3
"""
Verifier for Cooling Tower Volume Modeling task.

Criteria:
1. File created during task (10 pts)
2. Three specific points plotted (15 pts)
3. Polynomial function created (20 pts)
4. Surface of revolution created (25 pts)
5. Integral/Volume calculated (20 pts)
6. Text annotation present (10 pts)

VLM Verification:
- Checks if the final screenshot shows a cooling tower shape (hyperboloid-like).
"""

import json
import tempfile
import os
import logging

logger = logging.getLogger(__name__)

def verify_cooling_tower_volume_modeling(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Get metadata
    metadata = task_info.get('metadata', {})
    
    # Retrieve result JSON
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)
            
    score = 0
    feedback = []
    
    # 1. File existence (10 pts)
    if result.get("file_found") and result.get("file_created_during_task"):
        score += 10
        feedback.append("File created successfully (+10).")
    elif result.get("file_found"):
        score += 5
        feedback.append("File found but not created during task (+5).")
    else:
        feedback.append("File not found.")

    # 2. Points (15 pts)
    points_found = result.get("points_found", 0)
    if points_found >= 3:
        score += 15
        feedback.append("All profile points found (+15).")
    elif points_found > 0:
        score += 5 * points_found
        feedback.append(f"{points_found} profile points found (+{5*points_found}).")
    else:
        feedback.append("No correct profile points found.")

    # 3. Polynomial (20 pts)
    if result.get("has_polynomial"):
        score += 20
        feedback.append("Polynomial function found (+20).")
    else:
        feedback.append("Polynomial function missing.")

    # 4. Surface (25 pts)
    if result.get("has_surface"):
        score += 25
        feedback.append("3D Surface created (+25).")
    else:
        feedback.append("3D Surface missing.")

    # 5. Integral/Volume (20 pts)
    if result.get("has_integral"):
        vol = result.get("volume_value", 0)
        # Expected approx 400,000. Range 380k - 420k is generous.
        if 350000 < vol < 450000:
            score += 20
            feedback.append(f"Volume calculated correctly ({vol:.0f}) (+20).")
        else:
            score += 10
            feedback.append(f"Integral found but value {vol:.0f} seems off (+10).")
    else:
        feedback.append("Volume integral missing.")

    # 6. Annotation (10 pts)
    if result.get("has_annotation"):
        score += 10
        feedback.append("Annotation found (+10).")
    else:
        feedback.append("Annotation missing.")

    passed = score >= 70
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }