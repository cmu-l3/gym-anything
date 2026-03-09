#!/usr/bin/env python3
"""
Verifier for soft_body_jello_simulation task.

Criteria:
1. File created/modified (10 pts)
2. Collision modifier on Plate (20 pts)
3. Soft Body modifier on JellySuzanne (20 pts)
4. Soft Body Settings (Goal enabled, reasonable strength) (20 pts)
5. Physics Simulation Check (Object falls AND deforms) (30 pts)

Pass Threshold: 75 points
"""

import json
import tempfile
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_soft_body_simulation(traj, env_info, task_info):
    """
    Verify the soft body simulation setup and behavior.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Framework error: copy_from_env missing"}

    metadata = task_info.get('metadata', {})
    
    # 1. Load result JSON
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            data = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback = []
    
    # Analysis data from Blender Python script
    analysis = data.get("analysis", {})
    if not analysis.get("exists", False):
        return {"passed": False, "score": 0, "feedback": "Project file jello_sim.blend not found"}

    # Criterion 1: File created (10 pts)
    if data.get("file_created", False):
        score += 10
        feedback.append("File created")
    else:
        feedback.append("File exists but timestamp indicates it wasn't modified")
        
    modifiers = analysis.get("modifiers", {})
    settings = analysis.get("settings", {})
    physics = analysis.get("physics_test", {})

    # Criterion 2: Collision Modifier (20 pts)
    if modifiers.get("collision"):
        score += 20
        feedback.append("Collision modifier present")
    else:
        feedback.append("Missing Collision modifier on Plate")

    # Criterion 3: Soft Body Modifier (20 pts)
    if modifiers.get("soft_body"):
        score += 20
        feedback.append("Soft Body modifier present")
    else:
        feedback.append("Missing Soft Body modifier on JellySuzanne")
        # If no soft body, we can't really score the rest well
        return {"passed": False, "score": score, "feedback": "; ".join(feedback)}

    # Criterion 4: Soft Body Settings (20 pts)
    # Requirement: Goal enabled, strength 0.3-0.9, Edges enabled
    sb_points = 0
    if settings.get("use_goal"):
        goal = settings.get("goal_default", 1.0)
        if 0.3 <= goal <= 0.9:
            sb_points += 10
            feedback.append(f"Goal strength good ({goal:.2f})")
        else:
            feedback.append(f"Goal strength {goal:.2f} out of ideal range (0.3-0.9)")
    else:
        feedback.append("Goal disabled (risk of collapse)")
        
    if settings.get("use_edges"):
        sb_points += 10
        feedback.append("Edges/Springs enabled")
    else:
        feedback.append("Edges disabled")
        
    score += sb_points

    # Criterion 5: Physical Reaction (30 pts)
    # Verified by running simulation steps in export_result.sh
    phys_points = 0
    if physics.get("falls"):
        phys_points += 10
        feedback.append("Object falls correctly")
        
        if physics.get("bounces"):
            phys_points += 10
            feedback.append("Object hits plate and stops/bounces")
        else:
            feedback.append("Object fell through plate or flew away")
            
        if physics.get("deforms"):
            phys_points += 10
            feedback.append("Object deforms (squishes) on impact")
        else:
            feedback.append("Object too stiff (no deformation detected)")
    else:
        feedback.append("Object did not fall (Gravity/Simulation issue)")
        
    score += phys_points

    return {
        "passed": score >= 75,
        "score": score,
        "feedback": "; ".join(feedback),
        "details": {
            "physics_stats": physics,
            "settings": settings
        }
    }