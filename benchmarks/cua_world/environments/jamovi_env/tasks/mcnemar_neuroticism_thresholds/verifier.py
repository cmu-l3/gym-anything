#!/usr/bin/env python3
"""
Verifier for McNemar's Test on Neuroticism Thresholds task.

Criteria:
1. Jamovi project (.omv) created and modified during task.
2. Computed variables (N1_Binary, N2_Binary) exist in .omv metadata.
3. McNemar analysis exists in .omv metadata.
4. Reported p-value matches ground truth calculated from source data.
"""

import json
import os
import sys
import tempfile
import logging
import zipfile
import re
import csv
from scipy import stats
import numpy as np

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def calculate_ground_truth(csv_path):
    """Calculate McNemar p-value from source CSV."""
    try:
        n1_vals = []
        n2_vals = []
        
        with open(csv_path, 'r') as f:
            reader = csv.DictReader(f)
            for row in reader:
                try:
                    # N1 and N2 are likely columns
                    n1 = float(row.get('N1', 0))
                    n2 = float(row.get('N2', 0))
                    n1_vals.append(1 if n1 > 3 else 0)
                    n2_vals.append(1 if n2 > 3 else 0)
                except ValueError:
                    continue
        
        if not n1_vals:
            return None

        # Create contingency table
        #     N2=0  N2=1
        # N1=0  a     b
        # N1=1  c     d
        
        b = sum(1 for i in range(len(n1_vals)) if n1_vals[i] == 0 and n2_vals[i] == 1)
        c = sum(1 for i in range(len(n1_vals)) if n1_vals[i] == 1 and n2_vals[i] == 0)
        
        # McNemar calculation (Chi-square approx)
        # chi2 = (b - c)^2 / (b + c)
        if b + c == 0:
            return 1.0
            
        chi2 = ((abs(b - c) - 1.0) ** 2) / (b + c) # Continuity correction is standard in some tools, Jamovi often uses exact or continuity corrected
        # Let's calculate exact binomial if numbers are small, or chi2.
        # Jamovi usually reports exact p-value (binomial) for 2x2 or Chi-square.
        # We will compute both and accept either.
        
        p_chi2 = stats.chi2.sf(chi2, 1)
        p_exact = stats.binomtest(b, b+c, 0.5).pvalue
        
        return {"p_chi2": p_chi2, "p_exact": p_exact, "b": b, "c": c}
        
    except Exception as e:
        logger.error(f"Error calculating ground truth: {e}")
        return None

def verify_mcnemar_neuroticism_thresholds(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Environment copy missing"}

    score = 0
    feedback = []
    
    # 1. Retrieve Result JSON
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result: {e}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    # 2. Retrieve Files
    omv_path = result.get("omv_path")
    report_path = result.get("report_path")
    csv_path = result.get("source_csv_path")
    
    local_omv = tempfile.NamedTemporaryFile(delete=False, suffix='.omv').name
    local_report = tempfile.NamedTemporaryFile(delete=False, suffix='.txt').name
    local_csv = tempfile.NamedTemporaryFile(delete=False, suffix='.csv').name
    
    files_retrieved = {}
    try:
        if result.get("omv_exists"):
            copy_from_env(omv_path, local_omv)
            files_retrieved["omv"] = True
        
        if result.get("report_exists"):
            copy_from_env(report_path, local_report)
            files_retrieved["report"] = True
            
        # Always try to get CSV for ground truth
        copy_from_env(csv_path, local_csv)
        files_retrieved["csv"] = True
    except Exception:
        pass # Handle missing files in scoring

    # CRITERION 1: OMV File Exists & Created During Task (20 pts)
    if files_retrieved.get("omv") and result.get("omv_created_during_task"):
        score += 20
        feedback.append("Project file created successfully.")
        
        # Check OMV Internal Structure (Variables and Analysis)
        try:
            with zipfile.ZipFile(local_omv, 'r') as z:
                # Check for metadata (Manifest or meta)
                file_list = z.namelist()
                
                # Simple heuristic: Check if computed variables exist in metadata
                # Note: Jamovi structure is complex, often JSONs in 'meta' folder
                found_vars = False
                found_analysis = False
                
                for filename in file_list:
                    if filename.endswith(".json") or filename.endswith(".yaml"):
                        content = z.read(filename).decode('utf-8', errors='ignore')
                        if "N1_Binary" in content and "N2_Binary" in content:
                            found_vars = True
                        if "mcnemar" in content.lower() or "paired samples" in content.lower():
                            found_analysis = True
                
                if found_vars:
                    score += 20
                    feedback.append("Computed variables found in project.")
                else:
                    feedback.append("Computed variables NOT found in project.")
                    
                if found_analysis:
                    score += 20
                    feedback.append("McNemar/Paired analysis found in project.")
                else:
                    feedback.append("Analysis definition NOT found in project.")
                    
        except zipfile.BadZipFile:
            feedback.append("Project file is corrupted.")
    else:
        feedback.append("Project file missing or not created during task.")

    # CRITERION 2: Report Content & Accuracy (40 pts)
    gt = calculate_ground_truth(local_csv)
    p_value_reported = None
    
    if files_retrieved.get("report"):
        try:
            with open(local_report, 'r') as f:
                content = f.read()
                # extract number
                match = re.search(r"p_value:?\s*([0-9\.]+)", content, re.IGNORECASE)
                if match:
                    p_value_reported = float(match.group(1))
        except Exception:
            feedback.append("Could not parse report file.")

    if p_value_reported is not None and gt:
        # Check against both Exact and Chi-squared approx
        # Tolerance 0.005 for rounding differences
        matches_exact = abs(p_value_reported - gt['p_exact']) < 0.005
        matches_chi2 = abs(p_value_reported - gt['p_chi2']) < 0.005
        
        if matches_exact or matches_chi2:
            score += 40
            feedback.append(f"Reported p-value ({p_value_reported}) is correct.")
        else:
            feedback.append(f"Reported p-value ({p_value_reported}) differs from ground truth (Exact: {gt['p_exact']:.4f}, Chi2: {gt['p_chi2']:.4f}).")
    elif p_value_reported is not None:
        score += 10 # Partial credit for format
        feedback.append("Reported p-value found but could not verify against ground truth.")
    else:
        feedback.append("No valid p-value found in report.")

    # Cleanup
    for f in [local_omv, local_report, local_csv]:
        if os.path.exists(f):
            os.unlink(f)

    return {
        "passed": score >= 70,
        "score": score,
        "feedback": " ".join(feedback)
    }