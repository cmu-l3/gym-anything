#!/usr/bin/env python3
"""
Verifier for QBlade Ncrit Roughness Study Task.

Verifies:
1. Results text file exists and parses correctly.
2. QBlade project file exists and is valid.
3. Physical consistency of results (Roughness should decrease Cl_max, increase Cd_min).
4. VLM verification of the workflow (NACA generator used -> XFoil Polars generated).
"""

import json
import base64
import re
import os
import tempfile
import logging
from typing import Dict, Any

# Gym-Anything VLM utilities
try:
    from gym_anything.vlm import sample_trajectory_frames, query_vlm
except ImportError:
    # Mock for local testing if needed
    def sample_trajectory_frames(traj, n=5): return []
    def query_vlm(**kwargs): return {"success": False, "error": "VLM not available"}

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def parse_results_text(content_b64: str) -> Dict[str, float]:
    """Parses the base64 encoded report content."""
    try:
        text = base64.b64decode(content_b64).decode('utf-8', errors='ignore')
    except Exception:
        return {}
    
    data = {}
    
    # Extract Clean values
    clean_section = re.search(r"CLEAN CASE.*?(\n\n|\Z)", text, re.DOTALL | re.IGNORECASE)
    if clean_section:
        c_text = clean_section.group(0)
        cl_match = re.search(r"Cl_max:\s*([0-9.]+)", c_text)
        cd_match = re.search(r"Cd_min:\s*([0-9.]+)", c_text)
        if cl_match: data['clean_cl_max'] = float(cl_match.group(1))
        if cd_match: data['clean_cd_min'] = float(cd_match.group(1))

    # Extract Rough values
    rough_section = re.search(r"ROUGH CASE.*?(\n\n|\Z)", text, re.DOTALL | re.IGNORECASE)
    if rough_section:
        r_text = rough_section.group(0)
        cl_match = re.search(r"Cl_max:\s*([0-9.]+)", r_text)
        cd_match = re.search(r"Cd_min:\s*([0-9.]+)", r_text)
        if cl_match: data['rough_cl_max'] = float(cl_match.group(1))
        if cd_match: data['rough_cd_min'] = float(cd_match.group(1))
        
    return data

def verify_ncrit_study(traj, env_info, task_info):
    """
    Main verification function.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    ranges = metadata.get('ranges', {})

    # Load result JSON
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
    feedback = []
    
    # ---------------------------------------------------------
    # Criterion 1: Files Existence & Anti-Gaming (25 pts)
    # ---------------------------------------------------------
    files_ok = False
    if result.get('report_exists') and result.get('report_created_during_task'):
        score += 15
        feedback.append("Results report file created during task.")
        files_ok = True
    else:
        feedback.append("Results report file missing or not created during task.")

    if result.get('project_exists') and result.get('project_created_during_task'):
        # Check for non-trivial size (>1KB)
        if result.get('project_size_bytes', 0) > 1024:
            score += 10
            feedback.append("QBlade project file saved.")
        else:
            feedback.append("QBlade project file is empty/corrupt.")
    else:
        feedback.append("QBlade project file missing.")

    # ---------------------------------------------------------
    # Criterion 2: Data Validity & Physics (40 pts)
    # ---------------------------------------------------------
    parsed_data = parse_results_text(result.get('report_content_b64', ''))
    
    clean_cl = parsed_data.get('clean_cl_max')
    rough_cl = parsed_data.get('rough_cl_max')
    clean_cd = parsed_data.get('clean_cd_min')
    rough_cd = parsed_data.get('rough_cd_min')
    
    data_valid = False
    
    if clean_cl is not None and rough_cl is not None:
        # Check ranges
        c_range = ranges.get('clean_cl_max', [1.4, 1.85])
        if c_range[0] <= clean_cl <= c_range[1]:
            score += 5
        else:
            feedback.append(f"Clean Cl_max {clean_cl} out of expected range {c_range}.")

        # Check Physics: Roughness should reduce Cl_max
        if clean_cl > rough_cl:
            score += 10
            feedback.append(f"Physics Check Passed: Roughness reduced Cl_max ({clean_cl} -> {rough_cl}).")
            data_valid = True
        elif clean_cl == rough_cl:
            feedback.append("Physics Check Failed: Clean and Rough Cl_max are identical (did you run the simulation twice with different settings?).")
        else:
            feedback.append("Physics Check Failed: Rough Cl_max is higher than Clean (unexpected).")
            
    else:
        feedback.append("Could not parse Cl_max values from report.")

    if clean_cd is not None and rough_cd is not None:
        # Check Physics: Roughness should increase Cd_min
        if rough_cd > clean_cd:
            score += 10
            feedback.append(f"Physics Check Passed: Roughness increased Cd_min ({clean_cd} -> {rough_cd}).")
        
        # Check range
        c_range = ranges.get('clean_cd_min', [0.005, 0.012])
        if c_range[0] <= clean_cd <= c_range[1]:
            score += 5

    if result.get('app_was_running'):
        score += 10
        feedback.append("QBlade was running at end of task.")

    # ---------------------------------------------------------
    # Criterion 3: VLM Workflow Verification (35 pts)
    # ---------------------------------------------------------
    # We sample frames to see if they actually did the work
    # This catches "just writing the text file without using the app"
    
    frames = sample_trajectory_frames(traj, n=6)
    vlm_prompt = """
    Analyze these screenshots of QBlade software.
    I am looking for evidence of two specific steps:
    1. "Airfoil Generation": A dialog or screen showing NACA parameters (like 'NACA 4412').
    2. "XFoil Analysis": A screen showing 'XFoil Direct Analysis', polar plots (curves), or simulation settings.
    
    Return JSON:
    {
        "naca_gen_visible": true/false,
        "xfoil_analysis_visible": true/false,
        "polar_plot_visible": true/false,
        "confidence": "high/medium/low"
    }
    """
    
    vlm_result = query_vlm(images=frames, prompt=vlm_prompt)
    
    if vlm_result.get("success"):
        parsed = vlm_result.get("parsed", {})
        if parsed.get("naca_gen_visible"):
            score += 10
            feedback.append("VLM confirmed NACA generator usage.")
        if parsed.get("xfoil_analysis_visible") or parsed.get("polar_plot_visible"):
            score += 25
            feedback.append("VLM confirmed XFoil analysis workflow.")
    else:
        # Fallback if VLM fails: verify strict file logic
        feedback.append("VLM verification unavailable.")
        if files_ok and data_valid:
            score += 20 # Give benefit of doubt if files are perfect

    # Final tally
    passed = (score >= 60) and files_ok and data_valid
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }