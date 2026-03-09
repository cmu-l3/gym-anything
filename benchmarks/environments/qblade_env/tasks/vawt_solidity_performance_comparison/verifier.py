#!/usr/bin/env python3
"""
Verifier for vawt_solidity_performance_comparison task.

Verification Strategy:
1. File Existence: Check if .wpa project and .txt report exist.
2. Anti-Gaming: Ensure files were created during the task.
3. Project Validation: Confirm the .wpa file contains evidence of two rotors with correct chords.
4. Report Logic: Parse the user's report to verify they identified the correct physical trend
   (Higher solidity/chord -> Lower Optimal TSR).
5. VLM Verification: Use trajectory frames to confirm QBlade usage (Airfoil -> Polar -> VAWT Design -> Simulation).
"""

import json
import base64
import re
import os
import tempfile
import logging
from gym_anything.vlm import sample_trajectory_frames, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_vawt_solidity_comparison(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Environment copy function unavailable"}

    # Load result JSON
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load task result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback = []
    
    # --- Criterion 1: Project File (30 pts) ---
    if result.get("project_exists") and result.get("file_created_during_task"):
        score += 15
        feedback.append("Project file created successfully.")
        
        # Check size (empty project is very small, < 1KB usually)
        if result.get("project_size", 0) > 5000:
            score += 15
            feedback.append("Project file size indicates content.")
        else:
            feedback.append("Project file seems too empty.")
    else:
        feedback.append("Project file not found or not created during task.")

    # --- Criterion 2: Project Content Hints (15 pts) ---
    # Derived from grep checks in export_result.sh
    content_score = result.get("project_content_score", 0)
    if content_score >= 3:
        score += 15
        feedback.append("Project contains evidence of correct config (Chords, DMS, Airfoil).")
    elif content_score >= 1:
        score += 5
        feedback.append("Project contains partial configuration evidence.")
    else:
        feedback.append("Project missing key configuration keywords.")

    # --- Criterion 3: Report Analysis (30 pts) ---
    report_exists = result.get("report_exists")
    report_valid = False
    
    if report_exists:
        try:
            content_b64 = result.get("report_content_b64", "")
            content = base64.b64decode(content_b64).decode('utf-8', errors='ignore').lower()
            
            # Extract TSR numbers near "rotor a" and "rotor b" or "0.15" and "0.3"
            # Simple heuristic: Look for lines with TSR and values
            
            # Check for mention of rotors
            if "rotor" in content or "chord" in content:
                score += 5
                feedback.append("Report format looks reasonable.")

            # Logic Check: High solidity (0.3m) should have LOWER optimal TSR than Low solidity (0.15m)
            # We look for a sentence or data implying B < A or 0.3 < 0.15 regarding TSR
            
            # Regex to find TSR values. E.g. "TSR = 2.5"
            # This is hard to parse perfectly without strict format, so we check for the text comparison
            if "lower" in content and ("rotor b" in content or "0.3" in content):
                # "Rotor B has lower optimal TSR"
                score += 25
                report_valid = True
                feedback.append("Report correctly identifies that higher solidity reduces optimal TSR.")
            elif "higher" in content and ("rotor a" in content or "0.15" in content):
                 # "Rotor A has higher optimal TSR"
                score += 25
                report_valid = True
                feedback.append("Report correctly identifies that lower solidity increases optimal TSR.")
            else:
                # Fallback: check if they just dumped numbers.
                # If we can't parse text logic, we rely on VLM to check the report screenshot if available, 
                # but here we'll be strict on the text report requirement.
                feedback.append("Report found but could not automatically verify the conclusion text.")
                # Give partial points if numbers are present
                if re.search(r'\d+\.?\d*', content):
                    score += 10
                    feedback.append("Report contains numerical data.")
        except Exception as e:
            feedback.append(f"Error parsing report: {e}")
    else:
        feedback.append("Report file not found.")

    # --- Criterion 4: VLM Trajectory Verification (25 pts) ---
    # We want to see QBlade being used, specifically the VAWT module.
    frames = sample_trajectory_frames(traj, n=4)
    
    vlm_prompt = """
    Analyze these screenshots of the QBlade software.
    I am looking for evidence of a VAWT (Vertical Axis Wind Turbine) design workflow.
    
    Look for:
    1. A vertical blade turbine (H-rotor) displayed in the viewport (looks like an H shape or vertical blades).
    2. Graphs or plots showing power curves (Cp vs TSR).
    3. Tables with simulation results.
    4. Mention of 'DMS' or 'Double Multiple Streamtube'.
    
    Return JSON:
    {
        "vawt_visible": boolean,
        "graphs_visible": boolean,
        "confidence": float (0-1)
    }
    """
    
    try:
        vlm_result = query_vlm(images=frames, prompt=vlm_prompt)
        parsed = vlm_result.get('parsed', {})
        
        if parsed.get('vawt_visible'):
            score += 15
            feedback.append("VLM confirmed VAWT design visible.")
        
        if parsed.get('graphs_visible'):
            score += 10
            feedback.append("VLM confirmed simulation graphs visible.")
            
    except Exception as e:
        logger.warning(f"VLM check failed: {e}")
        # Fallback points if VLM fails but files are perfect
        if score >= 60:
            score += 10
            feedback.append("VLM skipped (system error), fallback credit applied.")

    # Final Pass Check
    # Must have project file + report valid or VLM confirmation
    passed = (score >= 70) and result.get("project_exists")
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }