#!/usr/bin/env python3
"""
Verifier for QBlade NACA 23015 Workflow Task.
Verifies the existence and content of the QBlade project file (.wpa).
"""

import json
import os
import tempfile
import logging
import shutil
from gym_anything.vlm import sample_trajectory_frames, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_naca23015_workflow(traj, env_info, task_info):
    """
    Verifies the task based on:
    1. Output file existence and timestamp.
    2. Content analysis of the .wpa file (Airfoil, Re, Extrapolation).
    3. VLM trajectory verification.
    """
    
    # Setup
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System error: copy_from_env not available"}

    score = 0
    max_score = 100
    feedback = []
    
    # ------------------------------------------------------------------
    # 1. Retrieve Task Result Metadata
    # ------------------------------------------------------------------
    result_data = {}
    with tempfile.NamedTemporaryFile(suffix=".json") as tf:
        try:
            copy_from_env("/tmp/task_result.json", tf.name)
            tf.seek(0)
            result_data = json.load(tf)
        except Exception as e:
            return {"passed": False, "score": 0, "feedback": f"Failed to retrieve task result: {str(e)}"}

    # ------------------------------------------------------------------
    # 2. Verify File Existence & Anti-Gaming (30 pts)
    # ------------------------------------------------------------------
    if not result_data.get("file_exists", False):
        return {"passed": False, "score": 0, "feedback": "Project file 'naca23015_analysis.wpa' was not saved."}
    
    score += 10
    feedback.append("File exists.")

    if not result_data.get("file_created_during_task", False):
        feedback.append("WARNING: File timestamp predates task start.")
        # We penalize but don't fail immediately, though it's suspicious
    else:
        score += 10
        feedback.append("File created during task session.")

    if result_data.get("file_size", 0) > 1000: # WPA files are XML-ish, usually >1KB
        score += 10
        feedback.append("File size is valid.")
    else:
        feedback.append("File is suspiciously small/empty.")

    # ------------------------------------------------------------------
    # 3. Content Analysis of WPA File (45 pts)
    # ------------------------------------------------------------------
    # Retrieve the actual project file content
    wpa_content = ""
    with tempfile.NamedTemporaryFile(suffix=".wpa") as tf:
        try:
            copy_from_env("/tmp/exported_project.wpa", tf.name)
            # Read with errors='ignore' to handle potential encoding weirdness in QBlade files
            with open(tf.name, 'r', errors='ignore') as f:
                wpa_content = f.read()
        except Exception as e:
            feedback.append(f"Could not read project file content: {str(e)}")

    if wpa_content:
        # A. Check for Airfoil Name (15 pts)
        # QBlade stores names in various tags, searching for string is robust enough
        if "23015" in wpa_content or ("NACA" in wpa_content and "15" in wpa_content):
            score += 15
            feedback.append("NACA 23015 airfoil data found.")
        else:
            feedback.append("Could not find 'NACA 23015' identifier in project.")

        # B. Check for Reynolds Number 1,000,000 (15 pts)
        # QBlade often stores Re as "1000000" or scientific "1e+06"
        if "1000000" in wpa_content or "1e+06" in wpa_content or "1.000000e+06" in wpa_content:
            score += 15
            feedback.append("Reynolds number 1,000,000 found.")
        else:
            feedback.append("Specific Reynolds number (1,000,000) not found in project.")

        # C. Check for 360 Extrapolation (15 pts)
        # Look for Viterna keywords or extended Alpha ranges often stored in polar data
        # "Viterna" is the method name usually saved
        if "Viterna" in wpa_content or "360" in wpa_content:
            score += 15
            feedback.append("360-degree extrapolation data found.")
        else:
            # Fallback: look for high alpha values in data blocks
            # This is harder to regex reliably without parsing XML, but strict text search helps
            if "180.000" in wpa_content: # Common end point for 360 polar
                score += 15
                feedback.append("360-degree polar range detected.")
            else:
                feedback.append("360-degree extrapolation not explicitly confirmed.")

    # ------------------------------------------------------------------
    # 4. VLM Verification (25 pts)
    # ------------------------------------------------------------------
    # We use trajectory to ensure they actually used the software modules
    
    frames = sample_trajectory_frames(traj, n=4)
    vlm_prompt = """
    You are verifying a user using QBlade software. The user should have:
    1. Generated an airfoil (look for airfoil shape or NACA generator dialog).
    2. Run an XFoil Analysis (look for 'XFoil Direct Analysis' module, graphs of polars).
    3. Extrapolated the polar (look for 'Polar Extrapolation' module, 360 degree graphs).
    
    Examine the screenshots. Do you see evidence of these steps?
    Return JSON: {"evidence_airfoil": bool, "evidence_xfoil": bool, "evidence_extrapolation": bool}
    """
    
    try:
        vlm_res = query_vlm(prompt=vlm_prompt, images=frames)
        parsed = vlm_res.get('parsed', {})
        
        vlm_score = 0
        if parsed.get('evidence_airfoil'): vlm_score += 8
        if parsed.get('evidence_xfoil'): vlm_score += 9
        if parsed.get('evidence_extrapolation'): vlm_score += 8
        
        score += vlm_score
        if vlm_score > 15:
            feedback.append(f"VLM verified workflow steps ({vlm_score}/25 pts).")
        else:
            feedback.append(f"VLM found weak evidence of workflow ({vlm_score}/25 pts).")
            
    except Exception as e:
        logger.warning(f"VLM check failed: {e}")
        # Grant partial credit if programmatic checks passed to avoid punishing for VLM error
        if score >= 60:
            score += 15
            feedback.append("VLM unavailable, granted partial backup credit.")

    # ------------------------------------------------------------------
    # Final Decision
    # ------------------------------------------------------------------
    passed = (score >= 75)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }