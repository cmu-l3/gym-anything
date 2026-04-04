#!/usr/bin/env python3
import json
import os
import tempfile
import math
import logging
from typing import Dict, Any, List

# Setup logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger("verifier")

def calculate_anova_ground_truth(raw_data_path: str):
    """
    Re-calculate ANOVA statistics from the raw CSV data to compare against agent output.
    Since we generated the data in setup_task.ps1, we can re-compute the exact expected values.
    """
    try:
        import pandas as pd
        from scipy import stats
        
        # Read CSV
        df = pd.read_csv(raw_data_path)
        
        # Filter for valid data (BPXSY1 and BMICAT not null)
        df = df.dropna(subset=['BPXSY1', 'BMICAT'])
        
        groups = [df[df['BMICAT'] == i]['BPXSY1'].values for i in sorted(df['BMICAT'].unique())]
        
        # ANOVA
        f_stat, p_val = stats.f_oneway(*groups)
        
        # Kruskal-Wallis
        k_stat, k_p_val = stats.kruskal(*groups)
        
        # Mean of Obese (Cat 4)
        mean_obese = df[df['BMICAT'] == 4]['BPXSY1'].mean()
        
        return {
            "f_stat": f_stat,
            "p_val": p_val,
            "k_stat": k_stat,
            "mean_obese": mean_obese,
            "n_total": len(df)
        }
    except Exception as e:
        logger.error(f"Error computing ground truth: {e}")
        return None

def verify_anova_bp_by_bmi(traj, env_info, task_info):
    """
    Verifies the ANOVA task output.
    1. Checks if result file exists and was created during task.
    2. Parses values and compares with ground truth (calculated from the CSV used).
    3. Uses VLM to verify the workflow (Classic Analysis window, MEANS command).
    """
    
    # 1. Setup
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System error: copy_from_env not available"}

    # 2. Retrieve Result JSON
    temp_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("C:\\tmp\\task_result.json", temp_json.name)
        with open(temp_json.name, 'r') as f:
            result_data = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve task results: {str(e)}"}
    finally:
        if os.path.exists(temp_json.name):
            os.unlink(temp_json.name)

    # 3. Retrieve CSV for Ground Truth Calculation
    # We need the CSV to calculate the EXACT expected numbers, as they were generated randomly in setup
    temp_csv = tempfile.NamedTemporaryFile(delete=False, suffix='.csv')
    ground_truth = None
    try:
        # The path matches what's in task.json
        csv_path = "C:\\Users\\Docker\\Documents\\EpiProjects\\NhanesExam\\BPStudy.csv"
        copy_from_env(csv_path, temp_csv.name)
        ground_truth = calculate_anova_ground_truth(temp_csv.name)
    except Exception as e:
        logger.warning(f"Could not retrieve CSV for ground truth calc: {e}")
        # Fallback: check if ground truth was passed in result_data (the setup script calculated some means)
        # But for F-stat we really need the data. If this fails, we might rely on 'reasonable ranges'.
        pass
    finally:
        if os.path.exists(temp_csv.name):
            os.unlink(temp_csv.name)

    if not ground_truth:
        return {"passed": False, "score": 0, "feedback": "Failed to calculate ground truth from data"}

    # 4. Scoring Logic
    score = 0
    feedback = []
    
    # Criterion 1: Output File Existence (10 pts)
    if result_data.get('output_exists'):
        score += 10
        feedback.append("Output file found.")
    else:
        return {"passed": False, "score": 0, "feedback": "Output file 'anova_results.txt' not found."}

    # Criterion 2: Anti-Gaming / Freshness (10 pts)
    if result_data.get('output_created_during_task'):
        score += 10
        feedback.append("File created during task session.")
    else:
        feedback.append("Warning: File timestamp indicates it wasn't created during this session.")

    # Criterion 3: HTML Evidence (10 pts)
    if result_data.get('html_evidence_found'):
        score += 10
        feedback.append("Epi Info HTML analysis output found.")
    else:
        feedback.append("No Epi Info HTML output detected.")

    # Criterion 4: Value Verification (50 pts total)
    # Parse the user's file
    lines = result_data.get('output_lines', [])
    parsed_values = {}
    
    try:
        if len(lines) >= 5:
            parsed_values['f_stat'] = float(lines[0].strip())
            parsed_values['p_val'] = float(lines[1].strip())
            parsed_values['k_stat'] = float(lines[2].strip())
            parsed_values['mean_obese'] = float(lines[3].strip())
            parsed_values['n_total'] = int(float(lines[4].strip())) # Allow float formatting for int
        else:
            feedback.append(f"File has insufficient lines ({len(lines)}/5).")
    except ValueError:
        feedback.append("Error parsing numbers from output file.")

    # Helper for tolerance comparison
    def check_val(name, expected, actual, tol_pct=5.0, points=10):
        if actual is None: return 0
        
        # Absolute tolerance for small numbers (like p-value)
        if expected < 0.1:
            diff = abs(expected - actual)
            if diff < 0.05: return points
        else:
            # Relative tolerance
            pct_diff = abs(expected - actual) / (expected + 1e-9) * 100
            if pct_diff <= tol_pct: return points
            
        return 0

    # Score values
    s_f = check_val('F-Stat', ground_truth['f_stat'], parsed_values.get('f_stat'), 5.0, 10)
    s_p = check_val('P-Val', ground_truth['p_val'], parsed_values.get('p_val'), 5.0, 10) # Liberal tolerance for p-value formatting
    s_k = check_val('K-Stat', ground_truth['k_stat'], parsed_values.get('k_stat'), 5.0, 10)
    s_m = check_val('Mean Obese', ground_truth['mean_obese'], parsed_values.get('mean_obese'), 2.0, 10)
    s_n = check_val('N Total', ground_truth['n_total'], parsed_values.get('n_total'), 0.0, 10) # Exact match needed

    score += s_f + s_p + s_k + s_m + s_n
    
    if s_f > 0: feedback.append("F-statistic correct.")
    else: feedback.append(f"F-statistic mismatch (Exp: {ground_truth['f_stat']:.2f}, Got: {parsed_values.get('f_stat')})")
    
    if s_n > 0: feedback.append("Total count correct.")
    
    # Criterion 5: VLM Verification of Workflow (20 pts)
    # We use the standard GymAnything VLM helper (assumed imported or mocked here)
    # For this implementation file, we simulate the VLM check structure
    
    from gym_anything.vlm import sample_trajectory_frames, query_vlm
    
    frames = sample_trajectory_frames(traj, n=4)
    if frames:
        vlm_prompt = """
        Analyze these screenshots of Epi Info 7.
        I am looking for evidence that the user performed a MEANS analysis (ANOVA).
        
        Look for:
        1. The 'Classic Analysis' window (command prompt style interface).
        2. The 'MEANS' command being typed or displayed in the output.
        3. An ANOVA table or Means output in the browser/canvas area.
        
        Return JSON:
        {
            "classic_analysis_visible": boolean,
            "means_command_evidence": boolean,
            "anova_output_visible": boolean
        }
        """
        
        vlm_res = query_vlm(images=frames, prompt=vlm_prompt)
        if vlm_res.get('success'):
            parsed = vlm_res.get('parsed', {})
            if parsed.get('classic_analysis_visible'): score += 5
            if parsed.get('means_command_evidence'): score += 5
            if parsed.get('anova_output_visible'): score += 10
            feedback.append("VLM verification successful.")
        else:
            feedback.append("VLM verification failed to process.")
            # Fallback points if programmatic pass was strong
            if score >= 60: score += 10 
    else:
        feedback.append("No trajectory frames available for VLM.")

    passed = (score >= 70) and (s_f > 0 or s_p > 0) # Must have at least one main stat correct
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }