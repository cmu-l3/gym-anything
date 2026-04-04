#!/usr/bin/env python3
"""
Verifier for coxph_va_lungcancer task.

Verifies:
1. COXPH output file exists and was created during task.
2. COXPH output contains expected keywords (Anti-gaming).
3. Summary file contains correct extracted HR values.
4. VLM trajectory verification of command execution.
"""

import json
import tempfile
import os
import logging
import re
from gym_anything.vlm import sample_trajectory_frames, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_coxph_va_lungcancer(traj, env_info, task_info):
    """
    Verify Cox Proportional Hazards analysis.
    """
    # 1. Setup - Get Result JSON from container
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Copy result JSON
    temp_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        # Note: export script saved to C:\task_result.json
        # Docker/Windows usually maps this to root drive, path handling depends on specific gym impl
        # Assuming standard mapping
        copy_from_env("C:\\task_result.json", temp_json.name)
        with open(temp_json.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve task result: {e}"}
    finally:
        if os.path.exists(temp_json.name):
            os.unlink(temp_json.name)
    
    # 2. Copy the actual results file for content verification
    results_content = ""
    temp_txt = tempfile.NamedTemporaryFile(delete=False, suffix='.txt')
    try:
        if result.get('results_exists'):
            copy_from_env("C:\\Users\\Docker\\Documents\\EpiInfoData\\coxph_results.txt", temp_txt.name)
            with open(temp_txt.name, 'r', encoding='utf-8', errors='ignore') as f:
                results_content = f.read()
    except Exception:
        pass # It's okay if copy fails, we handle it in scoring
    finally:
        if os.path.exists(temp_txt.name):
            os.unlink(temp_txt.name)

    score = 0
    feedback = []

    # --- CRITERION 1: Results File Existence & Freshness (25 pts) ---
    if result.get('results_exists'):
        if result.get('results_fresh'):
            score += 25
            feedback.append("Results file created during task.")
        else:
            score += 10
            feedback.append("Results file exists but timestamp matches pre-task (or verify failed).")
    else:
        feedback.append("Results file NOT found.")

    # --- CRITERION 2: Content Check - Keywords (20 pts) ---
    # Check if the output actually looks like Epi Info COXPH output
    required_keywords = ["Hazard", "Ratio", "Confidence", "Probability", "Karnofsky", "Treatment"]
    found_keywords = [k for k in required_keywords if k in results_content]
    
    if len(found_keywords) >= 4:
        score += 20
        feedback.append("Results file content validated (COXPH keywords found).")
    elif len(found_keywords) > 0:
        score += 10
        feedback.append("Results file content partial match.")
    else:
        feedback.append("Results file appears empty or incorrect format.")

    # --- CRITERION 3: Summary File Values (30 pts) ---
    summary_content = result.get('summary_content', "")
    
    # Extract values using regex
    # Expected: HR_Karnofsky=0.967, HR_Treatment=1.02
    hr_k_match = re.search(r"HR_Karnofsky\s*=\s*([0-9\.]+)", summary_content)
    hr_t_match = re.search(r"HR_Treatment\s*=\s*([0-9\.]+)", summary_content)
    sig_k_match = re.search(r"Karnofsky_Significant\s*=\s*(Yes|No)", summary_content, re.IGNORECASE)
    
    # Check Karnofsky HR (Expect ~0.967)
    if hr_k_match:
        try:
            val = float(hr_k_match.group(1))
            if 0.94 <= val <= 0.99:
                score += 15
                feedback.append(f"Karnofsky HR correct ({val}).")
            else:
                feedback.append(f"Karnofsky HR out of range ({val}).")
        except:
            pass
            
    # Check Treatment HR (Expect ~1.02)
    if hr_t_match:
        try:
            val = float(hr_t_match.group(1))
            if 0.90 <= val <= 1.15:
                score += 10
                feedback.append(f"Treatment HR correct ({val}).")
            else:
                feedback.append(f"Treatment HR out of range ({val}).")
        except:
            pass
            
    # Check Significance (Karnofsky should be Yes/Significant)
    if sig_k_match:
        if sig_k_match.group(1).lower() == "yes":
            score += 5
            feedback.append("Significance inference correct.")

    # --- CRITERION 4: VLM Trajectory Verification (25 pts) ---
    # Sample 5 frames from the trajectory
    frames = sample_trajectory_frames(traj, n=5)
    
    vlm_prompt = """
    Analyze these screenshots of Epi Info 7.
    Look for evidence of the following workflow:
    1. Data loaded (Grid showing 'PatientID', 'Treatment', etc.)
    2. 'COXPH' or 'Cox Proportional Hazards' command being used.
    3. Output window showing statistical tables with 'Hazard Ratio'.
    
    Did the agent successfully run a Cox regression analysis?
    Respond with JSON: {"analysis_run": boolean, "data_visible": boolean}
    """
    
    vlm_result = query_vlm(images=frames, prompt=vlm_prompt)
    
    vlm_score = 0
    if vlm_result.get('success'):
        parsed = vlm_result.get('parsed', {})
        if parsed.get('analysis_run') or parsed.get('data_visible'):
            vlm_score += 25
            feedback.append("VLM confirms analysis workflow.")
        else:
            feedback.append("VLM did not observe analysis workflow.")
    else:
        # Fallback if VLM fails but file output is perfect
        if score >= 60:
            vlm_score += 15
            feedback.append("VLM skipped, trusting output files.")
            
    score += vlm_score

    # Final result
    passed = score >= 60
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }