#!/usr/bin/env python3
import json
import os
import tempfile
import base64
import pandas as pd
import numpy as np
from scipy.stats import chi2_contingency
import zipfile

def verify_stratified_chisquare_titanic(traj, env_info, task_info):
    """
    Verifies the Stratified Chi-Square task.
    
    Criteria:
    1. OMV project file exists and is a valid ZIP (Jamovi format).
    2. Report file exists and parses correctly.
    3. Reported statistics match Ground Truth (calculated from dataset).
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # 1. Retrieve Result JSON
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result_data = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result JSON: {str(e)}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    score = 0
    feedback = []
    
    # 2. Check OMV Project File (10 points)
    if result_data.get("omv_exists") and result_data.get("omv_created_during_task"):
        # Verify it's a valid zip (Jamovi files are zips)
        # We need to pull the actual file to verify integrity, but for now existence+size is a good proxy.
        # Actually, let's try to pull it to check if it's really an OMV
        try:
            temp_omv = tempfile.NamedTemporaryFile(delete=False, suffix='.omv')
            copy_from_env("/home/ga/Documents/Jamovi/TitanicStratified.omv", temp_omv.name)
            if zipfile.is_zipfile(temp_omv.name):
                score += 10
                feedback.append("Project saved correctly (.omv is valid).")
            else:
                feedback.append("Project file exists but is not a valid Jamovi archive.")
            os.unlink(temp_omv.name)
        except:
            feedback.append("Failed to verify OMV file integrity.")
    else:
        feedback.append("Project file not saved or created before task start.")

    # 3. Calculate Ground Truth
    # We need the dataset. We can assume it's the standard TitanicSurvival.csv.
    # To be robust, we'll download/load the specific one used in the env if possible, 
    # but since we can't easily execute in env, we'll download the standard one or use a hardcoded check if we are sure.
    # Best practice: Pull the dataset from the container to ensure we test what the agent used.
    
    try:
        temp_csv = tempfile.NamedTemporaryFile(delete=False, suffix='.csv')
        copy_from_env("/home/ga/Documents/Jamovi/TitanicSurvival.csv", temp_csv.name)
        df = pd.read_csv(temp_csv.name)
        os.unlink(temp_csv.name)
        
        # Ground Truth Calculation
        # Drop rows with missing values in relevant columns if Jamovi does that by default (it usually does listwise deletion)
        df_clean = df.dropna(subset=['sex', 'passengerClass', 'survived'])
        
        results_gt = {}
        for sex in ['female', 'male']:
            subset = df_clean[df_clean['sex'] == sex]
            # Create contingency table
            contingency = pd.crosstab(subset['passengerClass'], subset['survived'])
            chi2, p, dof, expected = chi2_contingency(contingency)
            results_gt[sex] = {'x2': chi2, 'p': p}
            
    except Exception as e:
        return {"passed": False, "score": score, "feedback": f"Verifier failed to calculate ground truth: {str(e)}"}

    # 4. Parse Agent Report (90 points distributed)
    report_b64 = result_data.get("report_content_b64", "")
    if not report_b64:
        feedback.append("Report file is missing or empty.")
        return {"passed": False, "score": score, "feedback": " ".join(feedback)}

    try:
        report_text = base64.b64decode(report_b64).decode('utf-8')
        lines = report_text.strip().split('\n')
        agent_vals = {}
        for line in lines:
            if '=' in line:
                key, val = line.split('=', 1)
                agent_vals[key.strip()] = float(val.strip())
        
        # Check Female Stats (45 pts)
        f_x2_gt = results_gt['female']['x2']
        f_p_gt = results_gt['female']['p']
        
        # Tolerances
        x2_tol = 1.0  # Chi-square values can vary slightly based on continuity correction (Jamovi usually does Pearson X2 without Yates by default for >2x2, but let's be lenient)
        p_tol = 0.001
        
        f_x2_ok = abs(agent_vals.get('Female_X2', -999) - f_x2_gt) < x2_tol
        f_p_ok = abs(agent_vals.get('Female_p', -999) - f_p_gt) < p_tol
        
        if f_x2_ok and f_p_ok:
            score += 45
            feedback.append("Female statistics correct.")
        else:
            feedback.append(f"Female stats incorrect. Expected X2≈{f_x2_gt:.2f}, Got {agent_vals.get('Female_X2')}")

        # Check Male Stats (45 pts)
        m_x2_gt = results_gt['male']['x2']
        m_p_gt = results_gt['male']['p']
        
        m_x2_ok = abs(agent_vals.get('Male_X2', -999) - m_x2_gt) < x2_tol
        m_p_ok = abs(agent_vals.get('Male_p', -999) - m_p_gt) < p_tol
        
        if m_x2_ok and m_p_ok:
            score += 45
            feedback.append("Male statistics correct.")
        else:
            feedback.append(f"Male stats incorrect. Expected X2≈{m_x2_gt:.2f}, Got {agent_vals.get('Male_X2')}")

    except Exception as e:
        feedback.append(f"Failed to parse report: {str(e)}")

    passed = score >= 90
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }