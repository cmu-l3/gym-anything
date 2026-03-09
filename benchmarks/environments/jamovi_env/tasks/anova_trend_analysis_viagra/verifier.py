#!/usr/bin/env python3
import json
import os
import zipfile
import tempfile
import re
import pandas as pd
import numpy as np
import scipy.stats as stats
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def calculate_ground_truth(csv_path):
    """
    Calculates the expected ANOVA and Trend Analysis values from the raw CSV.
    """
    try:
        df = pd.read_csv(csv_path)
        
        # Ensure correct types
        # Filter for relevant columns
        if 'dose' not in df.columns or 'libido' not in df.columns:
            return None
            
        groups = [df[df['dose'] == d]['libido'].values for d in sorted(df['dose'].unique())]
        
        # 1. Levene's Test (Homogeneity)
        levene_stat, levene_p = stats.levene(*groups)
        
        # 2. ANOVA
        f_stat, f_p = stats.f_oneway(*groups)
        
        # 3. Omega Squared
        # df_effect = k - 1 = 3 - 1 = 2
        # df_error = N - k = 15 - 3 = 12
        # MS_error = SS_error / df_error
        # SS_total
        
        k = len(groups)
        N = len(df)
        
        # Grand mean
        grand_mean = df['libido'].mean()
        
        # SS Total
        ss_total = np.sum((df['libido'] - grand_mean)**2)
        
        # SS Between (Effect)
        ss_between = sum(len(g) * (np.mean(g) - grand_mean)**2 for g in groups)
        
        # SS Within (Error)
        ss_error = sum(np.sum((g - np.mean(g))**2) for g in groups)
        
        df_between = k - 1
        df_error = N - k
        
        ms_error = ss_error / df_error
        
        omega_sq = (ss_between - (df_between * ms_error)) / (ss_total + ms_error)
        
        # 4. Polynomial Contrasts (Linear and Quadratic)
        # Using orthogonal polynomial coefficients for k=3:
        # Linear: -1, 0, 1
        # Quadratic: 1, -2, 1
        
        means = [np.mean(g) for g in groups]
        n_per_group = [len(g) for g in groups] # Assuming balanced for standard coefficients
        
        # Contrast L (Linear) = -1*M1 + 0*M2 + 1*M3
        psi_linear = -1*means[0] + 0*means[1] + 1*means[2]
        
        # Contrast Q (Quadratic) = 1*M1 - 2*M2 + 1*M3
        psi_quad = 1*means[0] - 2*means[1] + 1*means[2]
        
        # Standard Error for contrast: sqrt(MSE * sum(c_i^2 / n_i))
        # Assuming equal n=5
        n = 5
        se_linear = np.sqrt(ms_error * ((-1)**2/n + 0 + 1**2/n))
        se_quad = np.sqrt(ms_error * (1**2/n + (-2)**2/n + 1**2/n))
        
        t_linear = psi_linear / se_linear
        t_quad = psi_quad / se_quad
        
        # P-values (two-tailed)
        p_linear = 2 * (1 - stats.t.cdf(abs(t_linear), df=df_error))
        p_quad = 2 * (1 - stats.t.cdf(abs(t_quad), df=df_error))
        
        return {
            "levene_p": levene_stat, # Actually the logic returns stat, let's return p
            "levene_p_val": levene_p,
            "omega_sq": omega_sq,
            "linear_p": p_linear,
            "quadratic_p": p_quad
        }
    except Exception as e:
        logger.error(f"Error calculating ground truth: {e}")
        return None

def verify_anova_trend_analysis(traj, env_info, task_info):
    """
    Verifies that the agent:
    1. Configured the ANOVA correctly (Polynomial contrasts, Homogeneity, OmegaSq).
    2. Reported correct values in the text report.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    score = 0
    feedback = []
    
    # 1. Retrieve Result JSON
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result = json.load(f)
    except Exception:
        return {"passed": False, "score": 0, "feedback": "Failed to load task result JSON"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)
            
    # Check if files exist
    if not result.get("omv_exists") or not result.get("report_exists"):
        return {"passed": False, "score": 0, "feedback": "Missing output files (OMV or Report)"}
        
    score += 10 # Files exist
    if result.get("omv_created_during_task"): score += 5
    if result.get("report_created_during_task"): score += 5
    
    # 2. Analyze OMV File (Configuration Verification)
    temp_omv = tempfile.NamedTemporaryFile(delete=False, suffix='.omv')
    omv_passed = False
    try:
        copy_from_env(result["omv_path"], temp_omv.name)
        
        # OMV is a ZIP. We look for 'analysis' definitions in JSON files inside.
        with zipfile.ZipFile(temp_omv.name, 'r') as z:
            # Jamovi saves analyses in numbered files or meta, but usually there is an index.
            # We scan all .json files for the ANOVA configuration.
            found_config = False
            for filename in z.namelist():
                if filename.endswith('.json'):
                    try:
                        with z.open(filename) as f:
                            data = json.load(f)
                            # Look for ANOVA structure
                            # Typical keys: "type": "jmv::ANOVA" or "gamlj::..."
                            # Options: "contrasts", "homo", "effectSize"
                            
                            # Note: The structure is deeply nested. We search recursively or textually.
                            content_str = json.dumps(data)
                            
                            # Check basic ANOVA presence
                            if "jmv::ANOVA" in content_str or "ANOVA" in content_str:
                                # Check specific settings
                                has_poly = False
                                has_omega = False
                                has_homo = False
                                
                                # Parsing options dictionary if possible, otherwise regex on the dump
                                # "contrasts":[{"var":"dose","type":"polynomial"}]
                                if re.search(r'"type":\s*"polynomial"', content_str, re.IGNORECASE):
                                    has_poly = True
                                
                                # "effectSize":["omega"] or similar
                                if "omega" in content_str.lower():
                                    has_omega = True
                                    
                                # "homo":true
                                if '"homo":true' in content_str.replace(" ", ""):
                                    has_homo = True
                                    
                                if has_poly and has_omega and has_homo:
                                    score += 40
                                    found_config = True
                                    feedback.append("Correct ANOVA configuration found (Polynomial, Omega, Homogeneity).")
                                    omv_passed = True
                                    break
                                elif has_poly:
                                    score += 20
                                    feedback.append("Polynomial contrasts found.")
                                    if has_omega: score += 10; feedback.append("Omega squared found.")
                                    if has_homo: score += 10; feedback.append("Homogeneity check found.")
                                    found_config = True
                                    break
                    except:
                        continue
            if not found_config:
                feedback.append("Could not find correct ANOVA configuration in OMV file.")
    except Exception as e:
        feedback.append(f"Error analyzing OMV: {e}")
    finally:
        if os.path.exists(temp_omv.name):
            os.unlink(temp_omv.name)

    # 3. Analyze Report File (Value Verification)
    # Calculate Ground Truth first
    # We need the dataset. We can copy it from env or assume standard values.
    # To be robust, let's copy the csv from env.
    temp_csv = tempfile.NamedTemporaryFile(delete=False, suffix='.csv')
    gt = None
    try:
        copy_from_env("/home/ga/Documents/Jamovi/Viagra.csv", temp_csv.name)
        gt = calculate_ground_truth(temp_csv.name)
    except:
        # Fallback values for Field(2013) Viagra dataset
        gt = {
            "levene_p_val": 0.89,  # Approx
            "omega_sq": 0.35,      # Approx
            "linear_p": 0.009,     # Significant < .01
            "quadratic_p": 0.45    # Not significant
        }
        feedback.append("Used fallback ground truth.")
    finally:
        if os.path.exists(temp_csv.name):
            os.unlink(temp_csv.name)
            
    # Read Report
    temp_report = tempfile.NamedTemporaryFile(delete=False, suffix='.txt')
    report_score = 0
    try:
        copy_from_env(result["report_path"], temp_report.name)
        with open(temp_report.name, 'r') as f:
            content = f.read()
            
        # Extract numbers using Regex
        # Expected format: Key: Value
        # But we just look for floating point numbers and try to match them to GT
        
        # Simple extraction of all floats
        floats = [float(x) for x in re.findall(r"[-+]?\d*\.\d+|\d+", content)]
        
        if len(floats) >= 4:
            # We don't know the order for sure if labels aren't strictly parsed, 
            # but the prompt asked for Levene, Linear, Quadratic, Omega.
            # Let's try to parse by label if possible, else positional.
            
            # Robust parsing
            val_levene = None
            val_lin = None
            val_quad = None
            val_omega = None
            
            lines = content.lower().splitlines()
            for line in lines:
                v = re.findall(r"[-+]?\d*\.\d+", line)
                if not v: continue
                val = float(v[0])
                
                if "levene" in line: val_levene = val
                elif "linear" in line: val_lin = val
                elif "quad" in line: val_quad = val
                elif "omega" in line: val_omega = val
            
            # If labels missing, fallback to position
            if val_levene is None and len(floats) >= 1: val_levene = floats[0]
            if val_lin is None and len(floats) >= 2: val_lin = floats[1]
            if val_quad is None and len(floats) >= 3: val_quad = floats[2]
            if val_omega is None and len(floats) >= 4: val_omega = floats[3]
            
            # Check values
            # Levene P (High, > 0.05)
            if gt and abs(val_levene - gt['levene_p_val']) < 0.1:
                report_score += 10
            
            # Linear P (Significant, < 0.05)
            if gt and abs(val_lin - gt['linear_p']) < 0.05:
                report_score += 10
                
            # Quadratic P (Non-sig, > 0.05)
            if gt and abs(val_quad - gt['quadratic_p']) < 0.1:
                report_score += 10
                
            # Omega Sq (around 0.3-0.4)
            if gt and abs(val_omega - gt['omega_sq']) < 0.1:
                report_score += 10
                
            if report_score >= 30:
                feedback.append("Reported values match ground truth.")
            else:
                feedback.append(f"Reported values deviate. Found: {floats}, Expected approx: {gt}")
        else:
            feedback.append("Report did not contain enough numerical values.")
            
    except Exception as e:
        feedback.append(f"Error analyzing report: {e}")
    finally:
        if os.path.exists(temp_report.name):
            os.unlink(temp_report.name)
            
    score += report_score
    
    passed = score >= 70
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }