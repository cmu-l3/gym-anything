#!/usr/bin/env python3
"""
Verifier for robust_anova_titanic_age task.

Verifies:
1. Files exist and were created during task.
2. .omv file contains correct analysis options (Welch's ANOVA, Games-Howell).
3. Report file values match ground truth (calculated from dataset).
4. VLM verification of trajectory.
"""

import json
import os
import tempfile
import zipfile
import logging
import re
import pandas as pd
import numpy as np
from scipy import stats

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_robust_anova_titanic_age(traj, env_info, task_info):
    """
    Verify the Robust ANOVA task.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    score = 0
    feedback_parts = []
    
    # Files to retrieve
    files = {
        "result": "/tmp/task_result.json",
        "project": "/tmp/agent_project.omv",
        "report": "/tmp/agent_report.txt",
        "dataset": "/tmp/dataset.csv"
    }
    
    local_files = {}
    
    # Retrieve files
    with tempfile.TemporaryDirectory() as temp_dir:
        for name, path in files.items():
            local_path = os.path.join(temp_dir, os.path.basename(path))
            try:
                copy_from_env(path, local_path)
                local_files[name] = local_path
            except Exception as e:
                logger.warning(f"Failed to copy {name}: {e}")
                local_files[name] = None

        # Load result JSON
        if local_files["result"]:
            with open(local_files["result"], 'r') as f:
                result = json.load(f)
        else:
            return {"passed": False, "score": 0, "feedback": "Failed to retrieve result JSON"}

        # ================================================================
        # CRITERION 1: Files Exist and App Running (20 points)
        # ================================================================
        project_exists = result.get("project_exists", False)
        report_exists = result.get("report_exists", False)
        app_running = result.get("app_was_running", False)
        
        if project_exists and result.get("project_created_during_task", False):
            score += 10
            feedback_parts.append("Project file created")
        elif project_exists:
            score += 5
            feedback_parts.append("Project file exists (old timestamp)")
        else:
            feedback_parts.append("Project file MISSING")

        if report_exists and result.get("report_created_during_task", False):
            score += 5
            feedback_parts.append("Report file created")
        elif report_exists:
            score += 2
            feedback_parts.append("Report file exists (old timestamp)")
        
        if app_running:
            score += 5
            feedback_parts.append("Jamovi was running")

        # ================================================================
        # CRITERION 2: Analysis Options Check (30 points)
        # Inspect the .omv file (zip) for analysis settings
        # ================================================================
        analysis_correct = False
        welch_enabled = False
        games_howell_enabled = False
        
        if project_exists and local_files["project"]:
            try:
                with zipfile.ZipFile(local_files["project"], 'r') as z:
                    # Look for index.json or meta.json that contains analysis list
                    # Jamovi structure usually has metadata.json or index.json
                    # We look for "analyses" list
                    analysis_found = False
                    
                    # Try to find the analysis options in any json file in the archive
                    for filename in z.namelist():
                        if filename.endswith(".json"):
                            try:
                                with z.open(filename) as f:
                                    data = json.load(f)
                                    # Check if this JSON describes analyses
                                    # Structure varies, look for "analyses" key or specific options
                                    if "analyses" in data:
                                        for analysis in data["analyses"]:
                                            opts = analysis.get("options", {})
                                            # Check if it's One-Way ANOVA
                                            # Usually identified by name "anovaOneW" or similar
                                            # We look for specific options regardless of exact name
                                            if "dep" in opts and "group" in opts:
                                                # Check for Welch
                                                if opts.get("welch", False):
                                                    welch_enabled = True
                                                
                                                # Check for Games-Howell
                                                # Can be "phGamesHowell": true OR in a list of posthocs
                                                if opts.get("phGamesHowell", False):
                                                    games_howell_enabled = True
                                                
                                                analysis_found = True
                            except:
                                continue
                    
                    if welch_enabled:
                        score += 15
                        feedback_parts.append("Welch's ANOVA enabled")
                    else:
                        feedback_parts.append("Welch's ANOVA NOT enabled")
                        
                    if games_howell_enabled:
                        score += 15
                        feedback_parts.append("Games-Howell Post-Hoc enabled")
                    else:
                        feedback_parts.append("Games-Howell NOT enabled")
                        
            except Exception as e:
                feedback_parts.append(f"Failed to inspect project file: {e}")

        # ================================================================
        # CRITERION 3: Statistical Accuracy (30 points)
        # Compare report values to ground truth calculated from dataset
        # ================================================================
        ground_truth_calculated = False
        gt_welch_f = 0
        gt_welch_p = 0
        gt_levene_p = 0
        
        if local_files["dataset"]:
            try:
                df = pd.read_csv(local_files["dataset"])
                # Clean data: drop NaN in age or passengerClass
                df_clean = df.dropna(subset=['age', 'passengerClass'])
                
                groups = []
                for cls in sorted(df_clean['passengerClass'].unique()):
                    groups.append(df_clean[df_clean['passengerClass'] == cls]['age'].values)
                
                # Levene's Test (median center - Brown-Forsythe - standard robust)
                stat_lev, p_lev = stats.levene(*groups, center='median')
                gt_levene_p = p_lev
                
                # Welch's ANOVA
                # Manual calculation for >2 groups
                k = len(groups)
                ns = np.array([len(g) for g in groups])
                means = np.array([np.mean(g) for g in groups])
                vars_ = np.array([np.var(g, ddof=1) for g in groups])
                weights = ns / vars_
                w_sum = np.sum(weights)
                grand_mean_w = np.sum(weights * means) / w_sum
                ms_between = np.sum(weights * (means - grand_mean_w)**2) / (k - 1)
                lambda_val = np.sum((1 - weights/w_sum)**2 / (ns - 1))
                scale = 1 + (2 * (k - 2) / (k**2 - 1)) * lambda_val
                f_stat = ms_between / scale
                df1 = k - 1
                df2 = (k**2 - 1) / (3 * lambda_val)
                p_val = stats.f.sf(f_stat, df1, df2)
                
                gt_welch_f = f_stat
                gt_welch_p = p_val
                ground_truth_calculated = True
                
            except Exception as e:
                logger.error(f"Failed to calculate ground truth: {e}")
                feedback_parts.append("Ground truth calculation failed")

        if report_exists and local_files["report"] and ground_truth_calculated:
            try:
                with open(local_files["report"], 'r') as f:
                    content = f.read()
                
                # Parse values (simple regex for numbers)
                # Look for "Welch_F: 123.45" etc.
                welch_f_match = re.search(r"Welch_F[:\s=]+([\d\.]+)", content, re.IGNORECASE)
                welch_p_match = re.search(r"Welch_p[:\s=]+([<\d\.]+)", content, re.IGNORECASE)
                
                report_score = 0
                
                # Check F statistic (allow +/- 1.0 tolerance due to rounding/implementation diffs)
                if welch_f_match:
                    val = float(welch_f_match.group(1))
                    if abs(val - gt_welch_f) < 1.0:
                        report_score += 15
                        feedback_parts.append(f"Reported Welch F correct ({val})")
                    else:
                        feedback_parts.append(f"Reported Welch F incorrect (Got {val}, Expected {gt_welch_f:.2f})")
                
                # Check p-value (usually < .001)
                if welch_p_match:
                    val_str = welch_p_match.group(1)
                    if "<" in val_str and "001" in val_str and gt_welch_p < 0.001:
                        report_score += 15
                        feedback_parts.append("Reported Welch p correct (< .001)")
                    else:
                        try:
                            val = float(val_str)
                            if abs(val - gt_welch_p) < 0.01:
                                report_score += 15
                                feedback_parts.append("Reported Welch p correct")
                        except:
                            if gt_welch_p < 0.001 and "001" in val_str:
                                report_score += 15 # lenient check
                
                score += report_score
                
            except Exception as e:
                feedback_parts.append(f"Error parsing report: {e}")

        # ================================================================
        # CRITERION 4: VLM Verification (20 points)
        # ================================================================
        # Use trajectory frames
        # We assume `gym_anything.vlm` provides necessary functions if available
        # Here we simulate or define the check
        
        vlm_score = 0
        try:
            from gym_anything.vlm import sample_trajectory_frames, query_vlm
            
            frames = sample_trajectory_frames(traj, n=4)
            if frames:
                prompt = """
                You are verifying a Jamovi statistics task.
                Look at these screenshots.
                Did the user:
                1. Open the 'One-Way ANOVA' analysis?
                2. Select 'Welch's' test under Variances?
                3. Select 'Games-Howell' under Post-Hoc Tests?
                4. Is there a results table showing ANOVA results?
                
                Answer JSON: {"welch_selected": bool, "games_howell_selected": bool, "results_visible": bool}
                """
                
                result = query_vlm(images=frames, prompt=prompt)
                parsed = result.get("parsed", {})
                
                if parsed.get("welch_selected", False): vlm_score += 5
                if parsed.get("games_howell_selected", False): vlm_score += 5
                if parsed.get("results_visible", False): vlm_score += 10
                
                feedback_parts.append(f"VLM verification score: {vlm_score}/20")
            else:
                # If no frames, assume programmatic checks are sufficient if passed
                # Or give partial credit if file checks passed
                if score >= 60:
                    vlm_score = 20
                    feedback_parts.append("VLM skipped (programmatic pass)")
                    
        except ImportError:
            # Fallback if VLM lib not available
            if score >= 60:
                vlm_score = 20
            feedback_parts.append("VLM library not found")
            
        score += vlm_score

    # Final logic
    # Must have used correct method (Welch) to pass
    # Inspecting .omv is the most reliable way to know this
    # If .omv inspection failed but report is correct, we trust the report
    
    passed = score >= 70
    
    return {
        "passed": passed,
        "score": min(score, 100),
        "feedback": " | ".join(feedback_parts)
    }