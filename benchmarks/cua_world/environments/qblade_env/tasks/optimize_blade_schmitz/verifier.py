#!/usr/bin/env python3
"""
Verifier for optimize_blade_schmitz task.
Verifies QBlade workflow for aerodynamic blade optimization.
"""

import json
import os
import tempfile
import logging
import math
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_optimize_blade_schmitz(traj, env_info, task_info):
    """
    Verifies the blade optimization task using file checks and VLM trajectory analysis.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    min_cp = metadata.get('min_cp', 0.35)
    max_cp = metadata.get('max_cp', 0.55)
    target_tsr = metadata.get('target_tsr', 7.0)
    tsr_tolerance = metadata.get('tsr_tolerance', 1.0)
    min_project_size = metadata.get('min_project_size_bytes', 5000)

    # 1. Load Result JSON
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
    
    # --- CRITERION 1: File Existence & Anti-Gaming (25 pts) ---
    project_exists = result.get('project_exists', False)
    project_fresh = result.get('project_created_during_task', False)
    project_size = result.get('project_size_bytes', 0)
    results_file_exists = result.get('results_file_exists', False)

    if project_exists and project_fresh and project_size > min_project_size:
        score += 15
        feedback_parts.append("Valid project file created during task")
    elif project_exists:
        feedback_parts.append("Project file exists but failed validation (stale or empty)")
    else:
        feedback_parts.append("Project file not found")

    if results_file_exists:
        score += 10
        feedback_parts.append("Results text file found")

    # --- CRITERION 2: Physical Plausibility of Results (20 pts) ---
    try:
        cp_val = float(result.get('parsed_cp_max', 0))
        tsr_val = float(result.get('parsed_tsr_opt', 0))
        
        # Cp Validity
        if min_cp <= cp_val <= max_cp:
            score += 10
            feedback_parts.append(f"Cp_max ({cp_val}) is physically realistic")
        else:
            feedback_parts.append(f"Cp_max ({cp_val}) is outside expected range [{min_cp}-{max_cp}]")

        # TSR Validity
        if abs(tsr_val - target_tsr) <= tsr_tolerance:
            score += 10
            feedback_parts.append(f"Optimal TSR ({tsr_val}) matches design target")
        else:
            feedback_parts.append(f"Optimal TSR ({tsr_val}) deviates from target {target_tsr}")
    except ValueError:
        feedback_parts.append("Could not parse numeric results from text file")

    # --- CRITERION 3: VLM Trajectory Verification (55 pts) ---
    # We need to verify the *process* because the final file is just a binary blob.
    # We look for specific screens in QBlade.
    
    frames = sample_trajectory_frames(traj, n=8)
    final_screen = get_final_screenshot(traj)
    
    vlm_prompt = """
    You are verifying a user's workflow in the wind turbine software QBlade.
    The user was tasked with:
    1. Generating a NACA 4415 airfoil.
    2. Running XFoil analysis (Polar).
    3. Extrapolating the polar to 360 degrees.
    4. Designing a blade using the 'Optimize' feature (Schmitz/Betz).
    5. Running a BEM simulation (graph).

    Review the sequence of screenshots and answer the following JSON:
    {
        "generated_airfoil": boolean, // Did they see the NACA Generator or airfoil view?
        "ran_xfoil": boolean, // Did they see the XFoil/Polar view (graphs of Cl/Cd)?
        "extrapolated_360": boolean, // Did they see the 360 polar extrapolation view?
        "blade_design_optimized": boolean, // Did they use the Blade Design module? Look for a tapered blade (wide root, thin tip) or the 'Blade Optimization' dialog.
        "bem_simulation_graph": boolean, // Did they see a Cp vs TSR graph (bell curve)?
        "confidence": "high|medium|low"
    }
    """
    
    vlm_result = query_vlm(images=frames + [final_screen], prompt=vlm_prompt)
    
    if vlm_result.get('success'):
        parsed = vlm_result.get('parsed', {})
        logger.info(f"VLM Analysis: {parsed}")
        
        if parsed.get('generated_airfoil'):
            score += 10
            feedback_parts.append("VLM: Airfoil generation observed")
        
        if parsed.get('ran_xfoil'):
            score += 10
            feedback_parts.append("VLM: XFoil analysis observed")
            
        if parsed.get('extrapolated_360'):
            score += 5 # Smaller weight, sometimes hard to catch
            feedback_parts.append("VLM: Polar extrapolation observed")
            
        if parsed.get('blade_design_optimized'):
            score += 15
            feedback_parts.append("VLM: Blade optimization workflow observed")
            
        if parsed.get('bem_simulation_graph'):
            score += 15
            feedback_parts.append("VLM: BEM simulation results observed")
    else:
        feedback_parts.append("VLM verification failed (technical error)")

    # Final logic
    passed = score >= 60 and project_exists and project_fresh
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }