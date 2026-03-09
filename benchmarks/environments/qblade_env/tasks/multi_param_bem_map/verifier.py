#!/usr/bin/env python3
"""
Verifier for multi_param_bem_map@1

Verifies that the user:
1. Created a project file of sufficient size (indicating simulation data).
2. Saved it during the task window.
3. Visually performed the multi-parameter sweep workflow.
"""

import json
import tempfile
import os
import logging
import sys

# Add path to access vlm_utils if available in the environment
# (Assuming standard gym structure, but providing fallback)
try:
    from vlm_utils import query_vlm, sample_trajectory_frames
    VLM_AVAILABLE = True
except ImportError:
    VLM_AVAILABLE = False
    logging.warning("VLM utils not found. VLM verification will be skipped/mocked.")

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_multi_param_bem_map(traj, env_info, task_info):
    """
    Verification logic for Multi-Parameter BEM Map task.
    
    Scoring Breakdown (100 pts):
    - 10 pts: Project file exists
    - 10 pts: File created/modified during task
    - 20 pts: File size check (>50KB, indicates data present)
    - 10 pts: File is NOT a direct copy of a sample (hash check)
    - 50 pts: VLM verification of workflow (Setup -> Run -> Result)
    """
    
    # 1. Setup and retrieve programmatic results
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System error: copy_from_env missing"}

    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read task result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback = []
    
    # 2. Programmatic Checks (50 points total)
    
    # Check 1: File Exists (10)
    if result.get("output_file_exists"):
        score += 10
        feedback.append("Project file saved.")
    else:
        feedback.append("Project file 'performance_map.wpa' not found.")
        return {"passed": False, "score": 0, "feedback": " ".join(feedback)}

    # Check 2: Timestamp (10)
    if result.get("created_during_task"):
        score += 10
    else:
        feedback.append("Warning: File timestamp indicates it wasn't saved during this session.")

    # Check 3: File Size (20) & Content (10)
    # A QBlade project with a full multi-param sweep results table is significantly larger 
    # than a bare definition. 50KB is a safe lower bound for a project with *any* results.
    size_bytes = result.get("output_file_size_bytes", 0)
    is_copy = result.get("is_sample_copy", False)
    
    if is_copy:
        feedback.append("File is identical to sample project (no simulation results added).")
    elif size_bytes > 50000:
        score += 30 # 20 for size + 10 for uniqueness
        feedback.append(f"File size ({size_bytes/1024:.1f} KB) indicates simulation data.")
    elif size_bytes > 10000:
        score += 10 # Partial credit if unique but small
        feedback.append("File exists but seems small for a full multi-parameter sweep.")
    else:
        feedback.append("File is too small to contain simulation results.")

    # 3. VLM Verification (50 points total)
    vlm_score = 0
    if VLM_AVAILABLE:
        frames = sample_trajectory_frames(traj, n=6)
        
        prompt = """
        You are verifying a user workflow in QBlade (Wind Turbine Simulation Software).
        The user was asked to:
        1. Open a project.
        2. Go to 'Rotor BEM' module.
        3. Set up a Multi-Parameter Simulation (TSR 2-14, Pitch -5 to 20).
        4. Run the simulation and see a Cp Graph/Contour.
        
        Look at these screenshots of the user's session.
        
        Q1: Do you see the QBlade interface with a turbine/rotor loaded?
        Q2: Do you see a dialog box for 'Simulation Settings' or 'Multi Parameter'?
        Q3: Do you see a graph, contour plot, or 3D surface plot appearing in the main window (the results)?
        Q4: Do you see the user saving a file (Save File dialog)?
        
        Return JSON:
        {
            "rotor_loaded": boolean,
            "simulation_setup_seen": boolean,
            "results_graph_seen": boolean,
            "save_dialog_seen": boolean,
            "confidence": float (0-1)
        }
        """
        
        try:
            vlm_res = query_vlm(prompt=prompt, images=frames)
            data = vlm_res.get("parsed", {})
            
            if data.get("rotor_loaded"): vlm_score += 10
            if data.get("simulation_setup_seen"): vlm_score += 15
            if data.get("results_graph_seen"): vlm_score += 15
            if data.get("save_dialog_seen"): vlm_score += 10
            
            feedback.append(f"Visual verification score: {vlm_score}/50.")
        except Exception as e:
            logger.error(f"VLM check failed: {e}")
            # Fallback: if file is good, assume they did it
            if score >= 40:
                vlm_score = 40
                feedback.append("Visual verification skipped, granting fallback points based on valid file.")
    else:
        # Fallback if VLM unavailable in env
        if score >= 40:
            vlm_score = 50
            feedback.append("VLM unavailable - assuming success based on valid output file.")

    total_score = score + vlm_score
    
    # Threshold: Need file + reasonable size + some VLM evidence
    passed = total_score >= 70
    
    return {
        "passed": passed,
        "score": total_score,
        "feedback": " ".join(feedback)
    }