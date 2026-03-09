#!/usr/bin/env python3
"""
Verifier for Confidence Interval Estimation task.
Calculates ground truth statistics from the raw CSV and compares against
agent's reported values. Verify OMV file structure.
"""

import json
import os
import tempfile
import re
import math
import zipfile
import csv

def verify_confidence_interval_estimation(traj, env_info, task_info):
    """
    Verify the confidence interval task.
    1. Calculate ground truth from CSV.
    2. Check reported values in text file.
    3. Verify OMV file exists and is valid.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Define paths
    data_path = task_info['metadata']['data_path']
    report_path = task_info['metadata']['report_path']
    omv_path = task_info['metadata']['omv_path']

    score = 0
    feedback_log = []
    
    # =========================================================
    # 1. Retrieve and Parse Data for Ground Truth
    # =========================================================
    temp_data = tempfile.NamedTemporaryFile(delete=False, suffix='.csv')
    try:
        copy_from_env(data_path, temp_data.name)
        
        # Parse CSV and calculate stats manually (avoiding pandas dependency if possible)
        groups = {} # {0: [val, val], 1: [val, val]}
        
        with open(temp_data.name, 'r') as f:
            reader = csv.DictReader(f)
            for row in reader:
                # Identify columns - allow for case variations
                keys = {k.lower(): k for k in row.keys()}
                mischief_key = keys.get('mischief')
                cloak_key = keys.get('cloak')
                
                if not mischief_key or not cloak_key:
                    continue
                    
                try:
                    val = float(row[mischief_key])
                    grp = int(float(row[cloak_key])) # Handle "0.0" or "0"
                    if grp not in groups:
                        groups[grp] = []
                    groups[grp].append(val)
                except ValueError:
                    continue

        # Calculate CIs (95%, t-distribution)
        ground_truth = {}
        for grp, values in groups.items():
            n = len(values)
            if n < 2:
                continue
            mean = sum(values) / n
            variance = sum((x - mean) ** 2 for x in values) / (n - 1)
            std_err = math.sqrt(variance / n)
            
            # T-critical for 95% (two-tailed 0.05) with df = n-1
            # Hardcoded small lookup table for robustness if scipy missing
            # or use scipy if available. 
            try:
                from scipy import stats
                t_crit = stats.t.ppf(0.975, n - 1)
            except ImportError:
                # Fallback for N=12 (common in this dataset)
                if n == 12:
                    t_crit = 2.201
                else:
                    # Approximation or generic fallback
                    t_crit = 1.96 + (2.4 / (n - 1)) # Rough approximation for small n

            margin = t_crit * std_err
            ground_truth[grp] = {
                'lower': mean - margin,
                'upper': mean + margin,
                'mean': mean
            }
            feedback_log.append(f"Ground Truth Grp {grp}: Mean={mean:.2f}, CI=[{mean-margin:.2f}, {mean+margin:.2f}]")
            
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Error calculating ground truth: {str(e)}"}
    finally:
        if os.path.exists(temp_data.name):
            os.unlink(temp_data.name)

    # =========================================================
    # 2. Check Agent Report
    # =========================================================
    temp_report = tempfile.NamedTemporaryFile(delete=False, suffix='.txt')
    try:
        copy_from_env(report_path, temp_report.name)
        with open(temp_report.name, 'r') as f:
            report_content = f.read()
            
        score += 10 # File exists
        feedback_log.append("Report file found.")

        # Regex to parse expected format
        # No Cloak (0) Lower: [value]
        # Allow some flexibility in case/spacing
        
        patterns = {
            (0, 'lower'): r"no\s*cloak.*?0.*?lower.*?:\s*([\d\.]+)",
            (0, 'upper'): r"no\s*cloak.*?0.*?upper.*?:\s*([\d\.]+)",
            (1, 'lower'): r"cloak.*?1.*?lower.*?:\s*([\d\.]+)",
            (1, 'upper'): r"cloak.*?1.*?upper.*?:\s*([\d\.]+)"
        }

        parsed_values = {}
        for key, pat in patterns.items():
            match = re.search(pat, report_content, re.IGNORECASE)
            if match:
                parsed_values[key] = float(match.group(1))

        # Compare values
        tolerance = 0.1
        
        # Check Group 0 (No Cloak)
        if 0 in ground_truth:
            gt = ground_truth[0]
            val_l = parsed_values.get((0, 'lower'))
            val_u = parsed_values.get((0, 'upper'))
            
            if val_l is not None and abs(val_l - gt['lower']) < tolerance:
                score += 17.5
            else:
                feedback_log.append(f"Group 0 Lower mismatch: Expected ~{gt['lower']:.2f}, Got {val_l}")

            if val_u is not None and abs(val_u - gt['upper']) < tolerance:
                score += 17.5
            else:
                feedback_log.append(f"Group 0 Upper mismatch: Expected ~{gt['upper']:.2f}, Got {val_u}")

        # Check Group 1 (Cloak)
        if 1 in ground_truth:
            gt = ground_truth[1]
            val_l = parsed_values.get((1, 'lower'))
            val_u = parsed_values.get((1, 'upper'))

            if val_l is not None and abs(val_l - gt['lower']) < tolerance:
                score += 17.5
            else:
                feedback_log.append(f"Group 1 Lower mismatch: Expected ~{gt['lower']:.2f}, Got {val_l}")

            if val_u is not None and abs(val_u - gt['upper']) < tolerance:
                score += 17.5
            else:
                feedback_log.append(f"Group 1 Upper mismatch: Expected ~{gt['upper']:.2f}, Got {val_u}")

    except Exception as e:
        feedback_log.append(f"Report check failed: {str(e)}")
    finally:
        if os.path.exists(temp_report.name):
            os.unlink(temp_report.name)

    # =========================================================
    # 3. Check OMV File
    # =========================================================
    temp_omv = tempfile.NamedTemporaryFile(delete=False, suffix='.omv')
    try:
        copy_from_env(omv_path, temp_omv.name)
        if zipfile.is_zipfile(temp_omv.name):
            score += 20
            feedback_log.append("Valid OMV file created.")
            
            # Optional: Inspect contents if strict verification needed
            # with zipfile.ZipFile(temp_omv.name, 'r') as z:
            #     if 'index.html' in z.namelist():
            #         score += 5
        else:
            feedback_log.append("OMV file exists but is not a valid zip/omv.")
            
    except Exception as e:
        feedback_log.append("OMV file missing or unreadable.")
    finally:
        if os.path.exists(temp_omv.name):
            os.unlink(temp_omv.name)

    # =========================================================
    # 4. Final Result
    # =========================================================
    passed = score >= 80
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_log)
    }