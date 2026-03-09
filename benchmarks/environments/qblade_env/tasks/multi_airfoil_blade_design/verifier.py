#!/usr/bin/env python3
"""
Verifier for QBlade Multi-Airfoil Blade Design Task.

Verifies:
1. File Creation: Checks if .wpa project file exists and was created during task.
2. Content Validation: Checks for presence of both required airfoils (4421, 4412) and blade definition.
3. VLM Verification: Analyzes trajectory to confirm workflow (Airfoil Gen -> XFoil -> Extrap -> Blade Design).
"""

import json
import os
import tempfile
import logging
from gym_anything.vlm import sample_trajectory_frames, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_multi_airfoil_blade_design(traj, env_info, task_info):
    """
    Verify the agent designed a multi-airfoil blade in QBlade.
    """
    # 1. Setup and Load Data
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System error: Copy function not available"}

    metadata = task_info.get('metadata', {})
    
    # Copy result JSON
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read task results: {str(e)}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    # 2. Programmatic Verification (60 points)
    score = 0
    feedback_parts = []
    
    # Check File Existence & Timestamp (20 pts)
    if result.get("output_exists") and result.get("file_created_during_task"):
        score += 20
        feedback_parts.append("Project file created successfully")
    elif result.get("output_exists"):
        score += 5
        feedback_parts.append("Project file exists but timestamp check failed (pre-existing?)")
    else:
        feedback_parts.append("Project file NOT found")

    # Check File Content (40 pts)
    # We look for evidence of both airfoils and a blade definition
    file_size = result.get("file_size_bytes", 0)
    has_4421 = result.get("contains_4421")
    has_4412 = result.get("contains_4412")
    has_blade = result.get("contains_blade_def")
    has_polar = result.get("contains_polar_data")

    if file_size > 2000: # Arbitrary threshold for non-empty project
        score += 5
    
    if has_4421 and has_4412:
        score += 15
        feedback_parts.append("Both airfoils (4421 & 4412) found in project")
    elif has_4421 or has_4412:
        score += 5
        feedback_parts.append("Only one required airfoil found")
    else:
        feedback_parts.append("Required airfoils missing from project file")

    if has_blade:
        score += 10
        feedback_parts.append("Blade definition found")
    else:
        feedback_parts.append("No blade definition found")

    if has_polar:
        score += 10
        feedback_parts.append("Polar data found")

    # 3. VLM Verification (40 points)
    # Check trajectory for workflow compliance
    frames = sample_trajectory_frames(traj, n=5)
    
    vlm_prompt = """
    You are verifying a QBlade wind turbine design workflow. 
    The user must:
    1. Generate two airfoils (look for airfoil shapes, 'NACA Generator' dialogs).
    2. Run XFoil analysis (look for graphs with 'Cl' vs 'Alpha' or 'Polar' views).
    3. Design a blade (look for a table of blade stations with 'Chord'/'Twist' columns or a 3D view of a blade).
    
    Based on these frames, did the agent perform these steps?
    """
    
    vlm_result = query_vlm(images=frames, prompt=vlm_prompt)
    
    vlm_score = 0
    if vlm_result and vlm_result.get("success"):
        # Heuristic: if VLM is positive about workflow
        analysis = vlm_result.get("text", "").lower()
        if "blade" in analysis and "design" in analysis:
            vlm_score += 10
        if "airfoil" in analysis or "naca" in analysis:
            vlm_score += 10
        if "graph" in analysis or "polar" in analysis or "plot" in analysis:
            vlm_score += 10
        if "yes" in analysis or "completed" in analysis or "success" in analysis:
            vlm_score += 10
            
        if vlm_score > 0:
            feedback_parts.append(f"VLM verified workflow steps ({vlm_score} pts)")
    else:
        feedback_parts.append("VLM verification failed to run")

    score += vlm_score

    # 4. Final Assessment
    # Must have file + blade def + decent score
    passed = (result.get("output_exists") and 
              result.get("file_created_during_task") and 
              has_blade and 
              score >= 70)

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }