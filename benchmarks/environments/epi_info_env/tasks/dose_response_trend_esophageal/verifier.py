#!/usr/bin/env python3
"""
Verifier for dose-response trend analysis task (Epi Info 7).

Verifies:
1. Analysis results file exists and contains correct statistical values (Chi-sq trend).
2. VLM trajectory shows correct workflow (Data import -> Analysis).
"""

import json
import os
import tempfile
import logging
import re
from gym_anything.vlm import sample_trajectory_frames, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_dose_response_trend(traj, env_info, task_info):
    """
    Verify the dose-response analysis task.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    score = 0
    feedback_parts = []
    
    # =========================================================
    # 1. Programmatic Verification (Results File)
    # =========================================================
    
    # Get the JSON result exported by the script
    task_result = {}
    temp_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("C:\\Users\\Docker\\Documents\\task_result.json", temp_json.name)
        with open(temp_json.name, 'r') as f:
            task_result = json.load(f)
    except Exception as e:
        feedback_parts.append(f"Could not read task status: {e}")
    finally:
        if os.path.exists(temp_json.name):
            os.unlink(temp_json.name)

    # Get the actual content of the results file
    results_content = ""
    temp_txt = tempfile.NamedTemporaryFile(delete=False, suffix='.txt')
    file_exists = task_result.get("output_exists", False)
    
    if file_exists:
        try:
            copy_from_env("C:\\Users\\Docker\\Documents\\EpiResults\\dose_response_results.txt", temp_txt.name)
            with open(temp_txt.name, 'r') as f:
                results_content = f.read()
            score += 10 # File exists
            feedback_parts.append("Results file found.")
            
            # Anti-gaming check
            if task_result.get("file_created_during_task", False):
                score += 10
                feedback_parts.append("File created during task.")
            else:
                feedback_parts.append("WARNING: File timestamp predates task start.")
        except Exception as e:
            feedback_parts.append(f"Failed to read results file: {e}")
    else:
        feedback_parts.append("Results file NOT found.")
    
    # Parse content
    parsed_vals = {}
    if results_content:
        for line in results_content.splitlines():
            if ':' in line:
                key, val = line.split(':', 1)
                parsed_vals[key.strip()] = val.strip()

    # Check Values
    # Alcohol Chi-Sq Trend (Expected > 50)
    alc_chisq = 0.0
    try:
        alc_chisq = float(parsed_vals.get("Alcohol_ChiSq_Trend", "0"))
        if 50.0 < alc_chisq < 200.0:
            score += 15
            feedback_parts.append(f"Alcohol Trend Chi-Sq correct ({alc_chisq}).")
        else:
            feedback_parts.append(f"Alcohol Trend Chi-Sq out of range ({alc_chisq}).")
    except:
        pass

    # Tobacco Chi-Sq Trend (Expected > 15)
    tob_chisq = 0.0
    try:
        tob_chisq = float(parsed_vals.get("Tobacco_ChiSq_Trend", "0"))
        if 15.0 < tob_chisq < 100.0:
            score += 15
            feedback_parts.append(f"Tobacco Trend Chi-Sq correct ({tob_chisq}).")
        else:
            feedback_parts.append(f"Tobacco Trend Chi-Sq out of range ({tob_chisq}).")
    except:
        pass
        
    # P-Values
    try:
        if float(parsed_vals.get("Alcohol_Trend_PValue", "1")) < 0.001:
            score += 5
    except: pass
    try:
        if float(parsed_vals.get("Tobacco_Trend_PValue", "1")) < 0.001:
            score += 5
    except: pass

    # =========================================================
    # 2. VLM Trajectory Verification
    # =========================================================
    
    frames = sample_trajectory_frames(traj, n=4)
    if frames:
        prompt = """
        Analyze these screenshots of Epi Info 7 Classic Analysis.
        The user should be performing a dose-response analysis.
        
        Look for:
        1. "READ" command or Data Grid showing loaded data.
        2. "TABLES" command output (blue/white tables).
        3. A "Chi-Square for Linear Trend" row in the statistics section of the output.
        
        Does the workflow show data loading and analysis execution?
        """
        
        vlm_res = query_vlm(prompt=prompt, images=frames)
        if vlm_res.get("success"):
            # Simple keyword matching in reasoning or a boolean parsed field if we used JSON mode
            # Here assuming a generic positive/negative check or mapped score
            # For robustness, we usually ask for JSON.
            
            # Let's try a JSON prompt for the VLM check
            json_prompt = """
            Analyze these screenshots. Did the user:
            1. Load data?
            2. Run a TABLES analysis?
            3. Is 'Chi-Square for Linear Trend' visible?
            
            Respond in JSON: {"data_loaded": bool, "analysis_run": bool, "trend_stat_visible": bool}
            """
            vlm_json = query_vlm(prompt=json_prompt, images=frames)
            
            if vlm_json.get("success"):
                parsed = vlm_json.get("parsed", {})
                if parsed.get("data_loaded"): score += 10
                if parsed.get("analysis_run"): score += 15
                if parsed.get("trend_stat_visible"): score += 15
                feedback_parts.append(f"VLM Analysis: {parsed}")
            else:
                # Fallback score if VLM technically worked but JSON parsing failed
                score += 20
                feedback_parts.append("VLM Verification partial (parsing failed).")
        else:
            feedback_parts.append("VLM Verification failed to run.")

    passed = score >= 60
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }