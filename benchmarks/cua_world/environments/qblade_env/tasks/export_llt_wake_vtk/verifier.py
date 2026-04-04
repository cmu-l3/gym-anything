#!/usr/bin/env python3
"""
Verifier for QBlade LLT Wake Simulation Task.

Criteria:
1. VTK file exists (30 pts)
2. VTK file is valid XML/VTK format & reasonable size (30 pts)
3. Project file saved (10 pts)
4. Files created DURING task session (Anti-gaming) (10 pts)
5. VLM Verification: Trajectory shows LLT/Wake visual (20 pts)
"""

import json
import tempfile
import os
import logging
from gym_anything.vlm import query_vlm, sample_trajectory_frames, get_final_screenshot

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_export_llt_wake_vtk(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System Error: Copy function not available"}

    # 1. Load result JSON
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
    
    # --- Criterion 1 & 4: VTK File Existence & Timing (40 pts total) ---
    vtk_exists = result.get("vtk_file_exists", False)
    vtk_fresh = result.get("vtk_created_during_task", False)
    
    if vtk_exists:
        if vtk_fresh:
            score += 40
            feedback.append("VTK file created successfully.")
        else:
            score += 10
            feedback.append("VTK file exists but has old timestamp (pre-existing?).")
    else:
        feedback.append("No 'wake_cutplane' VTK file found.")

    # --- Criterion 2: VTK Validity (30 pts) ---
    vtk_size = result.get("vtk_file_size", 0)
    vtk_header = result.get("vtk_header_snippet", "")
    
    # Real VTK files (XML based) usually start with <VTKFile... or look like XML
    # Legacy VTK starts with # vtk DataFile
    is_valid_format = "<VTKFile" in vtk_header or "# vtk DataFile" in vtk_header or "<?xml" in vtk_header
    
    if vtk_exists:
        if vtk_size > 10240: # >10KB implies real data
            if is_valid_format:
                score += 30
                feedback.append(f"VTK file is valid format and size ({vtk_size} bytes).")
            else:
                score += 15
                feedback.append("VTK file size ok, but header doesn't look like standard VTK.")
        else:
            feedback.append(f"VTK file is too small ({vtk_size} bytes) to contain wake data.")

    # --- Criterion 3: Project File (10 pts) ---
    if result.get("project_file_exists", False) and result.get("project_created_during_task", False):
        score += 10
        feedback.append("Project file saved.")

    # --- Criterion 5: VLM Verification (20 pts) ---
    # We look for visual evidence of the LLT simulation or Wake visualization
    frames = sample_trajectory_frames(traj, n=4)
    final_frame = get_final_screenshot(traj)
    if final_frame:
        frames.append(final_frame)
    
    if not frames:
        feedback.append("No screenshots available for visual verification.")
    else:
        vlm_prompt = """
        Review these screenshots of QBlade software.
        I am looking for evidence that the user performed a 'Lifting Line Theory (LLT)' simulation and visualized the wake.
        
        Look for:
        1. A 3D view showing a wind turbine.
        2. Colored flow lines, particles, or a 'cut plane' slice behind the turbine (the wake).
        3. Dialogs or panels with titles like 'LLT Simulation', 'QLLT', 'Simulation Settings', or 'Cut Plane'.
        
        Does the visual evidence suggest a wake simulation was run?
        Answer JSON: {"evidence_found": boolean, "reason": "string"}
        """
        
        try:
            vlm_res = query_vlm(prompt=vlm_prompt, images=frames)
            if vlm_res.get("success"):
                parsed = vlm_res.get("parsed", {})
                if parsed.get("evidence_found", False):
                    score += 20
                    feedback.append("Visual verification passed: Wake simulation observed.")
                else:
                    feedback.append(f"Visual verification failed: {parsed.get('reason', 'No wake visible')}")
            else:
                # Fallback if VLM fails: give partial credit if app was running and file is good
                if score >= 60: 
                    score += 10 
                    feedback.append("VLM failed, assuming visual pass based on file outputs.")
        except Exception as e:
            logger.error(f"VLM error: {e}")

    # --- Final Result ---
    # Threshold: Need valid VTK file (approx 70 pts implies file exists + valid + project saved or VLM pass)
    passed = score >= 70
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }