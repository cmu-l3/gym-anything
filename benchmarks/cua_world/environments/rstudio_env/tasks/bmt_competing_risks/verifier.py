#!/usr/bin/env python3
"""
Verifier for bmt_competing_risks task in RStudio.

Verification Strategy:
1. Programmatic File Check (20 pts): Ensure expected CSVs and PNG were created during the task.
2. Data Validation - CIF (20 pts): Parse `relapse_cif_estimates.csv`.
   - Verify values for Group 1 at 24 months are around ~0.32. (Standard KM gives ~0.45; this ensures competing risks math was applied).
3. Data Validation - Model (20 pts): Parse `fine_gray_model.csv`.
   - Verify presence of 'group3' covariate and that its HR > 1 (AML high risk patients have higher relapse).
4. Code Inspection (20 pts): Ensure the script uses `cuminc`, `crr`, or `finegray`.
5. VLM Visual Validation (20 pts): Verify RStudio coding trajectory and generated survival curves plot.

Adversarial protection:
- Mtime checks prevent using pre-existing files.
- Precise metric ranges prevent fake data/naive KM estimators.
- Trajectory VLM ensures the agent actually drove the UI.
"""

import json
import tempfile
import os
import csv
import logging
from typing import Dict, Any

logger = logging.getLogger(__name__)

# ================================================================
# VLM PROMPT
# ================================================================

TRAJECTORY_PROMPT = """You are analyzing screenshots from an agent performing a Competing Risks survival analysis in RStudio.

Please review these screenshots (sampled from the trajectory and the final frame) and assess:
1. Did the agent actively write R code? Look for evidence of typing in the script editor or console.
2. Did the agent execute the code? Look for console outputs, installed packages, or rendered plots.
3. Is a survival curve / cumulative incidence plot visible? This might be in the 'Plots' pane or as a standalone image viewer.

Respond ONLY in JSON format:
{
    "script_writing_visible": true/false,
    "code_execution_visible": true/false,
    "plot_visible": true/false,
    "confidence": "high/medium/low",
    "reasoning": "Brief explanation of what is visible"
}
"""

def verify_bmt_competing_risks(traj: Dict[str, Any], env_info: Dict[str, Any], task_info: Dict[str, Any]) -> Dict[str, Any]:
    copy_from_env = env_info.get('copy_from_env')
    query_vlm = env_info.get('query_vlm')
    
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Environment copy function missing"}
        
    score = 0
    feedback_parts = []
    
    # ----------------------------------------------------------------
    # 1. Fetch JSON and output files
    # ----------------------------------------------------------------
    with tempfile.TemporaryDirectory() as temp_dir:
        def fetch_file(container_path, local_name):
            local_path = os.path.join(temp_dir, local_name)
            try:
                copy_from_env(container_path, local_path)
                return local_path if os.path.exists(local_path) else None
            except Exception:
                return None

        result_path = fetch_file("/tmp/task_result.json", "result.json")
        cif_path = fetch_file("/tmp/cif_csv.csv", "cif.csv")
        model_path = fetch_file("/tmp/model_csv.csv", "model.csv")
        script_path = fetch_file("/tmp/script.R", "script.R")
        
        if not result_path:
            return {"passed": False, "score": 0, "feedback": "Task export JSON not found."}
            
        with open(result_path, 'r') as f:
            result = json.load(f)

        # ----------------------------------------------------------------
        # 2. File Metadata Checks (20 points)
        # ----------------------------------------------------------------
        cif_meta = result.get("cif_csv", {})
        model_meta = result.get("model_csv", {})
        plot_meta = result.get("plot_png", {})
        script_meta = result.get("script", {})
        
        meta_score = 0
        if cif_meta.get("exists") and cif_meta.get("is_new"): meta_score += 7
        if model_meta.get("exists") and model_meta.get("is_new"): meta_score += 7
        if plot_meta.get("exists") and plot_meta.get("is_new"): meta_score += 6
        
        score += meta_score
        feedback_parts.append(f"File creation score: {meta_score}/20")

        # ----------------------------------------------------------------
        # 3. Data Validation - CIF Estimates (20 points)
        # ----------------------------------------------------------------
        cif_score = 0
        if cif_path:
            try:
                with open(cif_path, 'r', encoding='utf-8') as f:
                    reader = csv.DictReader(f)
                    headers = [h.lower().strip() for h in (reader.fieldnames or [])]
                    
                    time_col = next((h for h in headers if 'time' in h or 't' == h), None)
                    group_col = next((h for h in headers if 'group' in h), None)
                    est_col = next((h for h in headers if any(k in h for k in ['est', 'prob', 'cif', 'inc', 'val'])), None)
                    
                    if time_col and group_col and est_col:
                        cif_score += 5  # Has recognizable columns
                        valid_cif_found = False
                        
                        for row in reader:
                            try:
                                g = str(row[group_col]).strip()
                                t = float(row[time_col])
                                e = float(row[est_col])
                                
                                # Check Group 1 at approx 24 months
                                if ('1' in g or 'ALL' in g.upper()) and (20 <= t <= 28):
                                    # True CIF is ~0.32. Standard KM is ~0.45.
                                    if 0.20 <= e <= 0.40:
                                        valid_cif_found = True
                            except (ValueError, TypeError):
                                continue
                                
                        if valid_cif_found:
                            cif_score += 15
                            feedback_parts.append("CIF values indicate competing risks correctly applied (+15)")
                        else:
                            feedback_parts.append("CIF estimates found, but values incorrect (KM used instead of CIF?) (+5)")
                    else:
                        feedback_parts.append("CIF CSV missing recognizable columns (group, time, estimate).")
            except Exception as e:
                feedback_parts.append(f"Error parsing CIF CSV: {e}")
        else:
            feedback_parts.append("CIF CSV missing.")
            
        score += cif_score
        
        # ----------------------------------------------------------------
        # 4. Data Validation - Model Summary (20 points)
        # ----------------------------------------------------------------
        model_score = 0
        if model_path:
            try:
                with open(model_path, 'r', encoding='utf-8') as f:
                    reader = csv.DictReader(f)
                    headers = [h.lower().strip() for h in (reader.fieldnames or [])]
                    
                    term_col = next((h for h in headers if any(k in h for k in ['term', 'var', 'cov'])), None)
                    coef_col = next((h for h in headers if 'coef' in h or 'estimate' in h), None)
                    hr_col = next((h for h in headers if 'hr' in h or 'ratio' in h or 'exp' in h), None)
                    
                    if term_col and (coef_col or hr_col):
                        model_score += 5
                        valid_group3 = False
                        
                        for row in reader:
                            term = str(row[term_col]).lower()
                            if 'group' in term and '3' in term:
                                try:
                                    # Group 3 (AML High Risk) should have positive coef (HR > 1) vs Group 1
                                    if hr_col and float(row[hr_col]) > 1.0:
                                        valid_group3 = True
                                    elif coef_col and float(row[coef_col]) > 0.0:
                                        valid_group3 = True
                                except (ValueError, TypeError):
                                    pass
                        if valid_group3:
                            model_score += 15
                            feedback_parts.append("Fine-Gray model covariates correctly evaluated (+15)")
                        else:
                            feedback_parts.append("Model CSV valid but missing/incorrect Group 3 effect (+5)")
                    else:
                        feedback_parts.append("Model CSV missing term/coef/hr columns.")
            except Exception as e:
                feedback_parts.append(f"Error parsing Model CSV: {e}")
        else:
            feedback_parts.append("Model CSV missing.")
            
        score += model_score

        # ----------------------------------------------------------------
        # 5. Code Validation (20 points)
        # ----------------------------------------------------------------
        code_score = 0
        if script_path and script_meta.get("is_new"):
            try:
                with open(script_path, 'r') as f:
                    code = f.read().lower()
                    
                # We need to see usage of competing risks methods
                if 'cuminc' in code:
                    code_score += 10
                if 'crr' in code or 'finegray' in code:
                    code_score += 10
                    
                if code_score > 0:
                    feedback_parts.append(f"Script verification passed ({code_score}/20)")
                else:
                    feedback_parts.append("Script does not appear to use cuminc or crr (0/20)")
            except Exception as e:
                feedback_parts.append(f"Error reading script: {e}")
                
        score += code_score

    # ----------------------------------------------------------------
    # 6. VLM Validation (20 points)
    # ----------------------------------------------------------------
    vlm_score = 0
    if query_vlm:
        from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot
        frames = sample_trajectory_frames(traj, n=4)
        final = get_final_screenshot(traj)
        if final:
            frames.append(final)
            
        try:
            vlm_response = query_vlm(prompt=TRAJECTORY_PROMPT, images=frames)
            if vlm_response.get("success"):
                parsed = vlm_response.get("parsed", {})
                if parsed.get("script_writing_visible"): vlm_score += 7
                if parsed.get("code_execution_visible"): vlm_score += 7
                if parsed.get("plot_visible"): vlm_score += 6
                
                feedback_parts.append(f"VLM trajectory score: {vlm_score}/20")
            else:
                feedback_parts.append("VLM analysis failed.")
        except Exception as e:
            feedback_parts.append(f"VLM exception: {e}")
            
    score += vlm_score

    passed = score >= 60 and (cif_score > 5 or model_score > 5)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": "\n".join(feedback_parts)
    }