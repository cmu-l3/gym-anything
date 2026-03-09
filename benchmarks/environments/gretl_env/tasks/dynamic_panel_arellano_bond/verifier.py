#!/usr/bin/env python3
"""
Verifier for dynamic_panel_arellano_bond task.
Checks for data download, script creation, correct estimation results, and diagnostic extraction.
"""

import json
import os
import tempfile
import logging
import re

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_dynamic_panel(traj, env_info, task_info):
    """
    Verify the Arellano-Bond estimation task.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    
    # Files to retrieve
    files_to_check = {
        "result_json": "/tmp/task_result.json",
        "script": metadata.get("script_path", "/home/ga/Documents/gretl_output/dynamic_panel.inp"),
        "results": metadata.get("results_path", "/home/ga/Documents/gretl_output/dpanel_results.txt"),
        "pvalue": metadata.get("pvalue_path", "/home/ga/Documents/gretl_output/ar2_pvalue.txt")
    }

    # Retrieve files
    local_files = {}
    for key, remote_path in files_to_check.items():
        try:
            temp_f = tempfile.NamedTemporaryFile(delete=False)
            temp_f.close()
            copy_from_env(remote_path, temp_f.name)
            local_files[key] = temp_f.name
        except Exception as e:
            logger.warning(f"Could not copy {key} from {remote_path}: {e}")
            local_files[key] = None

    score = 0
    feedback_parts = []
    
    # 1. Check Task Metadata (from export script)
    task_stats = {}
    if local_files["result_json"]:
        try:
            with open(local_files["result_json"], 'r') as f:
                task_stats = json.load(f)
        except:
            pass
            
    # Criterion 1: Data Downloaded (10 pts)
    dataset_info = task_stats.get("dataset", {})
    if dataset_info.get("exists") and dataset_info.get("size", 0) > 1000:
        score += 10
        feedback_parts.append("Dataset abdata.gdt downloaded successfully.")
    else:
        feedback_parts.append("Dataset abdata.gdt missing or empty.")

    # Criterion 2: Script Created & Valid (15 pts)
    script_info = task_stats.get("script", {})
    script_content = ""
    if script_info.get("exists") and local_files["script"]:
        try:
            with open(local_files["script"], 'r') as f:
                script_content = f.read()
            
            if "dpanel" in script_content or "diff-gmm" in script_content.lower():
                score += 15
                feedback_parts.append("Script contains dynamic panel command.")
            else:
                score += 5
                feedback_parts.append("Script file exists but 'dpanel' command not found.")
        except:
            pass
    else:
        feedback_parts.append("Script file missing.")

    # Criterion 3: Estimation Run & Results Valid (25 pts)
    results_info = task_stats.get("results", {})
    results_content = ""
    estimation_valid = False
    
    if results_info.get("exists") and local_files["results"]:
        try:
            with open(local_files["results"], 'r') as f:
                results_content = f.read()
                
            # Check for key phrases in output
            if "Model" in results_content and ("1-step" in results_content or "One-step" in results_content):
                estimation_valid = True
                score += 10
                feedback_parts.append("Estimation output found.")
                
            # Check for Arellano-Bond / Difference GMM indicators
            if "Arellano-Bond" in results_content or "Difference GMM" in results_content:
                score += 5
                
            # Check specific coefficient n(-1)
            # Regex to find coefficient for n(-1) or n_1
            # Line format often:  n(-1)      0.686226    0.144594     4.746   2.08e-06 ***
            match = re.search(r"n\(-1\)\s+([\-0-9\.]+)", results_content)
            if not match:
                # Try n_1 format
                match = re.search(r"n_1\s+([\-0-9\.]+)", results_content)
                
            if match:
                coeff = float(match.group(1))
                expected_range = metadata.get("expected_coeff_n_lag_range", [0.5, 0.9])
                if expected_range[0] <= coeff <= expected_range[1]:
                    score += 10
                    feedback_parts.append(f"Lagged dependent coefficient ({coeff}) is within expected range.")
                else:
                    feedback_parts.append(f"Lagged dependent coefficient ({coeff}) outside expected range {expected_range}.")
            else:
                feedback_parts.append("Could not parse n(-1) coefficient.")
                
        except Exception as e:
            feedback_parts.append(f"Error parsing results: {e}")
    else:
        feedback_parts.append("Estimation results file missing.")

    # Criterion 4: AR(2) P-value Extraction (25 pts)
    pvalue_info = task_stats.get("pvalue_file", {})
    ar2_valid = False
    
    if pvalue_info.get("exists") and local_files["pvalue"]:
        try:
            with open(local_files["pvalue"], 'r') as f:
                content = f.read().strip()
                
            # Try to parse a float number
            # Content might contain text like "p-value = 0.30" or just "0.30"
            match = re.search(r"([0-9]+\.[0-9]+)", content)
            if match:
                pval = float(match.group(1))
                expected_range = metadata.get("expected_ar2_pvalue_range", [0.20, 0.40])
                
                if expected_range[0] <= pval <= expected_range[1]:
                    score += 25
                    ar2_valid = True
                    feedback_parts.append(f"AR(2) p-value ({pval}) is correct.")
                else:
                    # Give partial credit if it looks like a probability but wrong range
                    if 0 <= pval <= 1:
                        score += 10
                        feedback_parts.append(f"AR(2) p-value ({pval}) extracted but outside expected range.")
                    else:
                        feedback_parts.append(f"Extracted value ({pval}) is not a valid probability.")
            else:
                feedback_parts.append("Could not parse number from p-value file.")
        except:
            feedback_parts.append("Error reading p-value file.")
    else:
        feedback_parts.append("AR(2) p-value file missing.")
        
    # Criterion 5: Evidence of Work (Artifacts created during task)
    # Checked via 'modified' flags in export_result.sh logic
    artifacts_created = (
        script_info.get("modified", False) and 
        results_info.get("modified", False) and 
        pvalue_info.get("modified", False)
    )
    
    if artifacts_created:
        score += 25
        feedback_parts.append("All artifacts created during task session.")
    elif score > 0:
        # Penalize if files pre-existed (anti-gaming), though setup should have cleared them
        score = max(0, score - 20)
        feedback_parts.append("Warning: Some artifacts may not have been created during this session.")

    # Cleanup
    for f in local_files.values():
        if f and os.path.exists(f):
            os.unlink(f)

    # Final decision
    # Must have valid estimation AND reasonable p-value extraction to pass
    passed = (score >= 75) and estimation_valid and ar2_valid

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }