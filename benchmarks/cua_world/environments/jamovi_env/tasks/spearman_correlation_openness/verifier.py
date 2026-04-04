#!/usr/bin/env python3
"""
Verifier for Spearman Correlation Matrix task in Jamovi.
Checks:
1. Report file existence and format.
2. Correct calculation of Spearman correlations (vs Ground Truth).
3. Identification of strongest/weakest pairs.
4. Visual verification (VLM) of 'Spearman' selection and UI state.
"""

import json
import os
import re
import tempfile
import logging
import pandas as pd
import numpy as np
from scipy.stats import spearmanr
from itertools import combinations
from gym_anything.vlm import sample_trajectory_frames, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_spearman_correlation(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # 1. Load Task Result
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            task_result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load task result: {e}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    # 2. Check basic file requirements
    if not task_result.get('output_exists', False):
        return {"passed": False, "score": 0, "feedback": "Report file not created."}
    
    if not task_result.get('file_created_during_task', False):
        return {"passed": False, "score": 0, "feedback": "Report file was not created during the task window."}

    # 3. Retrieve Data for Ground Truth Calculation
    # We copy the EXACT dataset used in the env to ensure 100% alignment
    temp_csv = tempfile.NamedTemporaryFile(delete=False, suffix='.csv')
    try:
        copy_from_env("/home/ga/Documents/Jamovi/BFI25.csv", temp_csv.name)
        df = pd.read_csv(temp_csv.name)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve dataset for verification: {e}"}
    finally:
        if os.path.exists(temp_csv.name):
            os.unlink(temp_csv.name)

    # 4. Calculate Ground Truth
    items = ['O1', 'O2', 'O3', 'O4', 'O5']
    correlations = {}
    significant_count = 0
    
    # Drop rows with missing values in these columns (though BFI25 is pre-cleaned)
    df_clean = df[items].dropna()
    
    for i, j in combinations(items, 2):
        rho, pval = spearmanr(df_clean[i], df_clean[j])
        key = f"{i}_{j}"
        # Store rho with 3 decimals
        correlations[key] = round(rho, 3)
        # Store reverse key too for easier lookup
        correlations[f"{j}_{i}"] = round(rho, 3)
        if pval < 0.05:
            significant_count += 1
            
    # Identify strongest/weakest (using absolute values)
    unique_pairs = list(combinations(items, 2))
    pair_stats = []
    for i, j in unique_pairs:
        key = f"{i}_{j}"
        val = correlations[key]
        pair_stats.append((key, val, abs(val)))
        
    pair_stats.sort(key=lambda x: x[2], reverse=True) # Sort by abs value desc
    
    gt_strongest_pair = pair_stats[0][0] # Key like "O1_O2"
    gt_strongest_val = pair_stats[0][1]
    
    gt_weakest_pair = pair_stats[-1][0]
    gt_weakest_val = pair_stats[-1][1]
    
    # 5. Parse User Report
    temp_report = tempfile.NamedTemporaryFile(delete=False, suffix='.txt')
    try:
        copy_from_env("/home/ga/Documents/Jamovi/spearman_openness_report.txt", temp_report.name)
        with open(temp_report.name, 'r') as f:
            report_lines = f.readlines()
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read report file: {e}"}
    finally:
        if os.path.exists(temp_report.name):
            os.unlink(temp_report.name)
            
    # Parsing logic
    user_data = {}
    for line in report_lines:
        line = line.strip()
        if ':' in line:
            parts = line.split(':', 1)
            key = parts[0].strip()
            val = parts[1].strip()
            user_data[key] = val

    # 6. Scoring
    score = 0
    feedback = []
    
    # Check specific correlations (Tolerance +/- 0.02)
    def check_val(key, target_val, pts):
        try:
            user_val = float(user_data.get(key, -999))
            if abs(user_val - target_val) <= 0.02:
                return pts, f"{key} Correct ({user_val})"
            return 0, f"{key} Incorrect (Expected {target_val}, Got {user_val})"
        except:
            return 0, f"{key} Missing or invalid format"

    # Specific pairs requested in task
    s1, f1 = check_val("O1_O2", correlations["O1_O2"], 10)
    score += s1; feedback.append(f1)
    
    s2, f2 = check_val("O2_O5", correlations["O2_O5"], 10)
    score += s2; feedback.append(f2)
    
    s3, f3 = check_val("O4_O5", correlations["O4_O5"], 10)
    score += s3; feedback.append(f3)
    
    # Strongest Pair
    u_strong_pair = user_data.get("strongest_pair", "").replace("-", "_")
    # Allow reverse order (e.g. O2_O1 vs O1_O2)
    pair_match = (u_strong_pair == gt_strongest_pair) or \
                 (u_strong_pair == "_".join(gt_strongest_pair.split("_")[::-1]))
    
    if pair_match:
        score += 15
        feedback.append(f"Strongest pair correct ({u_strong_pair})")
    else:
        feedback.append(f"Strongest pair incorrect (Expected {gt_strongest_pair}, Got {u_strong_pair})")
        
    s_srho, f_srho = check_val("strongest_rho", gt_strongest_val, 10)
    score += s_srho; feedback.append(f_srho)
    
    # Weakest Pair
    u_weak_pair = user_data.get("weakest_pair", "").replace("-", "_")
    pair_match_w = (u_weak_pair == gt_weakest_pair) or \
                   (u_weak_pair == "_".join(gt_weakest_pair.split("_")[::-1]))
                   
    if pair_match_w:
        score += 10
        feedback.append(f"Weakest pair correct ({u_weak_pair})")
    else:
        feedback.append(f"Weakest pair incorrect (Expected {gt_weakest_pair}, Got {u_weak_pair})")
        
    s_wrho, f_wrho = check_val("weakest_rho", gt_weakest_val, 5)
    score += s_wrho; feedback.append(f_wrho)
    
    # Significant Count
    try:
        u_sig = int(user_data.get("num_significant", -1))
        if u_sig == significant_count:
            score += 10
            feedback.append(f"Significant count correct ({u_sig})")
        else:
            feedback.append(f"Significant count incorrect (Expected {significant_count}, Got {u_sig})")
    except:
        feedback.append("Significant count invalid")

    # 7. VLM Verification (Trajectory-based)
    frames = sample_trajectory_frames(traj, n=5)
    
    vlm_prompt = """
    You are verifying a Jamovi statistics task. 
    Look at these screenshots of the user performing a Correlation Matrix analysis.
    
    Check for the following:
    1. Is 'Spearman' checked/selected in the Correlation Coefficients options?
    2. Is 'Pearson' unchecked?
    3. Are 'Confidence intervals' visible in the output table (e.g., columns saying 'Lower', 'Upper' or '95% CI')?
    4. Are significance flags (asterisks *) visible in the correlation matrix?
    
    Output JSON:
    {
        "spearman_selected": true/false,
        "pearson_unselected": true/false,
        "ci_visible": true/false,
        "flags_visible": true/false
    }
    """
    
    vlm_result = query_vlm(images=frames, prompt=vlm_prompt)
    vlm_score = 0
    if vlm_result.get("success"):
        parsed = vlm_result.get("parsed", {})
        if parsed.get("spearman_selected", False):
            vlm_score += 10
            feedback.append("VLM: Spearman selection confirmed.")
        else:
            feedback.append("VLM: Spearman selection NOT detected.")
            
        if parsed.get("ci_visible", False):
            vlm_score += 5
            feedback.append("VLM: Confidence Intervals detected.")
            
        if parsed.get("flags_visible", False):
            vlm_score += 5
            feedback.append("VLM: Significance flags detected.")
    else:
        feedback.append("VLM verification failed (technical error).")
        # Fallback: if data values are correct, assume they did it right.
        if score >= 50:
            vlm_score = 20
            feedback.append("Fallback: Data correct, awarding VLM points.")

    score += vlm_score

    # File existence points (already checked but awarding score)
    score += 5 

    passed = score >= 60 and s1 > 0 and s2 > 0  # Require some correct values to pass

    return {
        "passed": passed,
        "score": min(score, 100),
        "feedback": " | ".join(feedback)
    }