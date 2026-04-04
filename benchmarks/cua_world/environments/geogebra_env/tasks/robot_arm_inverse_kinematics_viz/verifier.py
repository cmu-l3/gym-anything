#!/usr/bin/env python3
"""
Verifier for Robot Arm Inverse Kinematics Visualizer.

Scoring (100 points total):
  - File created during task: 10 pts
  - Viewport adjusted (mm scale): 10 pts
  - Target point exists (free point): 10 pts
  - Link 1 length (290±1mm): 20 pts
  - Link 2 length (302±1mm): 20 pts
  - Kinematics Logic (Chain integrity): 20 pts
  - Workspace boundary (Circle 592): 10 pts
"""

import json
import tempfile
import os
import logging

logger = logging.getLogger(__name__)

def verify_robot_arm_inverse_kinematics_viz(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load result
    try:
        tmp = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        tmp.close()
        copy_from_env("/tmp/task_result.json", tmp.name)
        with open(tmp.name, 'r') as f:
            result = json.load(f)
        os.unlink(tmp.name)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result: {e}"}

    score = 0
    feedback = []
    
    # 1. File Created (10 pts)
    if result.get("file_found") and result.get("file_created_during_task"):
        score += 10
        feedback.append("File created successfully (+10).")
    else:
        feedback.append("File not found or old (+0).")

    # 2. Viewport Adjusted (10 pts)
    # If width > 200 (default is usually ~10-20), user zoomed out.
    vp_width = result.get("viewport_width", 0)
    if vp_width > 200:
        score += 10
        feedback.append(f"Viewport adjusted correctly (Width: ~{int(vp_width)} units) (+10).")
    else:
        feedback.append(f"Viewport too small ({int(vp_width)} units). Did you zoom out to millimeters? (+0).")

    # 3. Structure Analysis (Links & Elbow)
    candidates = result.get("elbow_candidates", [])
    link1_lengths = result.get("link1_lengths", [])
    link2_lengths = result.get("link2_lengths", [])
    
    # Link 1 correct
    if any(abs(l - 290) < 2.0 for l in link1_lengths):
        score += 20
        feedback.append("Link 1 length (290mm) correct (+20).")
    elif link1_lengths:
        feedback.append(f"Link 1 length incorrect. Found: {[int(l) for l in link1_lengths]} (+0).")
    else:
        feedback.append("Link 1 not found (+0).")

    # Link 2 correct
    if any(abs(l - 302) < 2.0 for l in link2_lengths):
        score += 20
        feedback.append("Link 2 length (302mm) correct (+20).")
    elif link2_lengths:
        feedback.append(f"Link 2 length incorrect. Found: {[int(l) for l in link2_lengths]} (+0).")
    else:
        feedback.append("Link 2 not found (+0).")
        
    # Kinematic Chain Integrity (Base -> Elbow -> Target)
    if len(candidates) > 0:
        score += 20
        feedback.append("Kinematic chain (Base-Elbow-Target) constructed correctly (+20).")
    else:
        feedback.append("Kinematic chain broken or missing. Ensure Elbow connects Base and Target (+0).")

    # 4. Target Point (10 pts)
    if result.get("target_found"):
        score += 10
        feedback.append("Target point identified (+10).")
    else:
        feedback.append("No draggable target point found (+0).")

    # 5. Workspace Boundary (10 pts)
    if result.get("workspace_circle_found"):
        score += 10
        feedback.append("Workspace boundary (Radius 592) found (+10).")
    else:
        feedback.append("Workspace boundary circle missing (+0).")

    return {
        "passed": score >= 70,
        "score": score,
        "feedback": " ".join(feedback)
    }