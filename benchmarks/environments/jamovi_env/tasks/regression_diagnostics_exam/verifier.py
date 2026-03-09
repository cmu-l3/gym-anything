#!/usr/bin/env python3
"""
Verifier for regression_diagnostics_exam task.

Checks:
1. OMV file creation (Application usage)
2. Text report existence and content (Numerical accuracy)
3. Timestamps (Anti-gaming)
"""

import json
import os
import re
import tempfile
import logging
import numpy as np
import pandas as pd

# Use statsmodels for ground truth regression if available, else numpy OLS
try:
    import statsmodels.api as sm
    from statsmodels.stats.outliers_influence import variance_inflation_factor
    from statsmodels.stats.stattools import durbin_watson
    STATSMODELS_AVAILABLE = True
except ImportError:
    STATSMODELS_AVAILABLE = False

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def parse_report(content):
    """Parse the agent's text report into a dictionary of values."""
    data = {}
    
    # R-squared: 0.123
    r2_match = re.search(r"R-squared:\s*([\d\.]+)", content, re.IGNORECASE)
    if r2_match: data['r2'] = float(r2_match.group(1))
    
    # Adjusted R-squared: 0.123
    adj_r2_match = re.search(r"Adjusted R-squared:\s*([\d\.]+)", content, re.IGNORECASE)
    if adj_r2_match: data['adj_r2'] = float(adj_r2_match.group(1))
    
    # Durbin-Watson: 1.567
    dw_match = re.search(r"Durbin-Watson:\s*([\d\.]+)", content, re.IGNORECASE)
    if dw_match: data['dw'] = float(dw_match.group(1))
    
    # Coefficients: Anxiety: B=..., Beta=..., p=...
    # Regex to capture named groups for Anxiety and Revise lines
    for var in ['Anxiety', 'Revise']:
        # Pattern looks for line starting with Var, then capturing B, Beta, p
        pattern = rf"{var}.*?B\s*=\s*([-\d\.]+).*?Beta\s*=\s*([-\d\.]+).*?p\s*=\s*([<\d\.]+)"
        match = re.search(pattern, content, re.IGNORECASE | re.DOTALL)
        if match:
            data[f'{var}_B'] = float(match.group(1))
            data[f'{var}_Beta'] = float(match.group(2))
            p_val_str = match.group(3)
            data[f'{var}_p'] = 0.001 if '<' in p_val_str else float(p_val_str)
            
    # VIF
    for var in ['Anxiety', 'Revise']:
        pattern = rf"{var}\s*VIF:\s*([\d\.]+)"
        match = re.search(pattern, content, re.IGNORECASE)
        if match:
            data[f'{var}_VIF'] = float(match.group(1))
            
    return data

def compute_ground_truth(csv_path):
    """Compute regression metrics using local python stack."""
    try:
        df = pd.read_csv(csv_path)
        # Drop rows with missing values in relevant columns
        df = df.dropna(subset=['Exam', 'Anxiety', 'Revise'])
        
        X = df[['Anxiety', 'Revise']]
        y = df['Exam']
        
        # Add constant for intercept
        X_const = sm.add_constant(X)
        
        model = sm.OLS(y, X_const).fit()
        
        results = {}
        results['r2'] = model.rsquared
        results['adj_r2'] = model.rsquared_adj
        results['dw'] = durbin_watson(model.resid)
        
        # Coefficients
        params = model.params
        results['Anxiety_B'] = params['Anxiety']
        results['Revise_B'] = params['Revise']
        
        # Standardized Coefficients (Beta)
        # Beta = B * (std(x) / std(y))
        results['Anxiety_Beta'] = params['Anxiety'] * (X['Anxiety'].std() / y.std())
        results['Revise_Beta'] = params['Revise'] * (X['Revise'].std() / y.std())
        
        # P-values
        results['Anxiety_p'] = model.pvalues['Anxiety']
        results['Revise_p'] = model.pvalues['Revise']
        
        # VIF
        # VIF for variable i is 1 / (1 - R_i^2) where R_i^2 is regression of i against other Xs
        # Or use statsmodels utility
        results['Anxiety_VIF'] = variance_inflation_factor(X_const.values, 1) # Index 1 matches Anxiety in X_const (0 is const)
        results['Revise_VIF'] = variance_inflation_factor(X_const.values, 2)
        
        return results, None
    except Exception as e:
        return None, str(e)

def verify_regression_diagnostics(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}
        
    score = 0
    feedback = []
    
    # 1. Retrieve Result JSON
    temp_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_json.name)
        with open(temp_json.name, 'r') as f:
            result_data = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve task result: {e}"}
    finally:
        if os.path.exists(temp_json.name): os.unlink(temp_json.name)

    # 2. Check OMV File (10 pts)
    if result_data.get("omv_exists") and result_data.get("omv_created_during_task") and result_data.get("omv_size", 0) > 1000:
        score += 10
        feedback.append("Jamovi project file saved.")
    else:
        feedback.append("Jamovi project file missing or not saved.")

    # 3. Retrieve and Parse Report
    report_content = ""
    if result_data.get("report_exists"):
        temp_report = tempfile.NamedTemporaryFile(delete=False, suffix='.txt')
        try:
            copy_from_env(result_data["report_path"], temp_report.name)
            with open(temp_report.name, 'r') as f:
                report_content = f.read()
            score += 10 # Report exists
            feedback.append("Report file found.")
        except Exception as e:
            feedback.append(f"Failed to read report: {e}")
        finally:
            if os.path.exists(temp_report.name): os.unlink(temp_report.name)
    else:
        feedback.append("Report file missing.")

    agent_vals = parse_report(report_content)
    
    # 4. Compute Ground Truth
    # Need to get dataset from env to compute ground truth
    temp_csv = tempfile.NamedTemporaryFile(delete=False, suffix='.csv')
    gt_vals = None
    try:
        copy_from_env(result_data["dataset_path"], temp_csv.name)
        if STATSMODELS_AVAILABLE:
            gt_vals, err = compute_ground_truth(temp_csv.name)
            if err:
                logger.error(f"GT Computation error: {err}")
                feedback.append(f"Verification error (GT computation): {err}")
        else:
            # Fallback hardcoded values for Exam Anxiety dataset (Field, 2013)
            # R2 = 0.210, Adj R2 = 0.194
            # Anxiety: B = -0.003, Beta = -0.006 (Insig), p=0.950 -- WAIT, typical result:
            # Actually, standard Exam Anxiety results:
            # Exam ~ Revise + Anxiety
            # Revise: Beta ~ 0.393, p < .001
            # Anxiety: Beta ~ -0.254, p = .009
            # R2 ~ 0.207
            # Let's rely on dynamic computation if possible, or strict tolerance if not.
            # Since I can't guarantee statsmodels, I will assume it's installed in the verifier env 
            # (standard for this benchmark) or use the fallback hardcoded from known literature if safe.
            # But the google:python_interpreter tool implies it's available. 
            # I will return a skip/fail if statsmodels is missing to be safe, or check imports.
            feedback.append("Statsmodels not available for verification.")
    except Exception as e:
        feedback.append(f"Failed to retrieve dataset: {e}")
    finally:
        if os.path.exists(temp_csv.name): os.unlink(temp_csv.name)

    if not gt_vals:
        return {"passed": False, "score": score, "feedback": " | ".join(feedback)}

    # 5. Compare Values (80 pts distributed)
    # Define tolerances
    TOL = {
        'r2': 0.02, 'adj_r2': 0.02,
        'dw': 0.15,
        'coef': 0.1,    # Unstandardized B
        'beta': 0.05,   # Standardized Beta
        'p': 0.01,
        'vif': 0.1
    }

    # Model Fit (15 pts)
    if 'r2' in agent_vals and abs(agent_vals['r2'] - gt_vals['r2']) < TOL['r2']:
        score += 8
    if 'adj_r2' in agent_vals and abs(agent_vals['adj_r2'] - gt_vals['adj_r2']) < TOL['adj_r2']:
        score += 7

    # Coefficients (30 pts)
    # Anxiety
    if 'Anxiety_B' in agent_vals and abs(agent_vals['Anxiety_B'] - gt_vals['Anxiety_B']) < TOL['coef']: score += 5
    if 'Anxiety_Beta' in agent_vals and abs(agent_vals['Anxiety_Beta'] - gt_vals['Anxiety_Beta']) < TOL['beta']: score += 5
    if 'Anxiety_p' in agent_vals and abs(agent_vals['Anxiety_p'] - gt_vals['Anxiety_p']) < TOL['p']: score += 5
    
    # Revise
    if 'Revise_B' in agent_vals and abs(agent_vals['Revise_B'] - gt_vals['Revise_B']) < TOL['coef']: score += 5
    if 'Revise_Beta' in agent_vals and abs(agent_vals['Revise_Beta'] - gt_vals['Revise_Beta']) < TOL['beta']: score += 5
    if 'Revise_p' in agent_vals and abs(agent_vals['Revise_p'] - gt_vals['Revise_p']) < TOL['p']: score += 5

    # Collinearity (20 pts)
    if 'Anxiety_VIF' in agent_vals and abs(agent_vals['Anxiety_VIF'] - gt_vals['Anxiety_VIF']) < TOL['vif']: score += 10
    if 'Revise_VIF' in agent_vals and abs(agent_vals['Revise_VIF'] - gt_vals['Revise_VIF']) < TOL['vif']: score += 10

    # Autocorrelation (15 pts)
    if 'dw' in agent_vals and abs(agent_vals['dw'] - gt_vals['dw']) < TOL['dw']: score += 15

    # Pass logic
    passed = (score >= 60)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": f"Score: {score}/100. " + " | ".join(feedback),
        "details": {
            "agent_values": agent_vals,
            "ground_truth": gt_vals
        }
    }