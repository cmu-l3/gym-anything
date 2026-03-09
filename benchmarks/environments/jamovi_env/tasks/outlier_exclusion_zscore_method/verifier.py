#!/usr/bin/env python3
import json
import os
import tempfile
import re
import csv
import math

def verify_outlier_exclusion(traj, env_info, task_info):
    """
    Verifies that the agent correctly calculated Z-scores, filtered outliers,
    and reported the correct statistics.
    """
    
    # 1. Setup and Environment Access
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Environment copy function missing"}

    # Define score components
    score = 0
    feedback = []
    
    # 2. Retrieve Files from Container
    temp_dir = tempfile.mkdtemp()
    result_json_path = os.path.join(temp_dir, "task_result.json")
    report_path = os.path.join(temp_dir, "outlier_report.txt")
    data_path = os.path.join(temp_dir, "source_data.csv")
    omv_path = os.path.join(temp_dir, "result.omv")

    try:
        copy_from_env("/tmp/task_result.json", result_json_path)
        with open(result_json_path, 'r') as f:
            task_result = json.load(f)
            
        # Copy data file to calculate ground truth
        copy_from_env("/tmp/source_data.csv", data_path)
        
        # Copy user report
        if task_result.get("report_exists"):
            copy_from_env("/tmp/outlier_report.txt", report_path)
            
        # Copy OMV file (just to verify it's a valid zip later)
        if task_result.get("omv_exists"):
            copy_from_env("/tmp/result.omv", omv_path)

    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve task files: {str(e)}"}

    # 3. Calculate Ground Truth
    try:
        ages = []
        with open(data_path, 'r') as f:
            reader = csv.DictReader(f)
            for row in reader:
                try:
                    # 'age' column check
                    val = row.get('age')
                    if val and val.strip():
                        ages.append(float(val))
                except ValueError:
                    continue
        
        if not ages:
            return {"passed": False, "score": 0, "feedback": "Could not read age data from source file"}

        n_original = len(ages)
        mean_original = sum(ages) / n_original
        variance = sum((x - mean_original) ** 2 for x in ages) / (n_original - 1)
        sd_original = math.sqrt(variance)

        # Apply Agent Logic: Z = (x - Mean) / SD
        # NOTE: Agents might use rounded values displayed in Jamovi (e.g., 2 decimals).
        # We calculate "strict" ground truth, but will allow tolerance.
        
        filtered_ages = []
        for x in ages:
            z_score = (x - mean_original) / sd_original
            if z_score <= 2.0:
                filtered_ages.append(x)
        
        n_filtered = len(filtered_ages)
        mean_filtered = sum(filtered_ages) / n_filtered
        excluded_count = n_original - n_filtered
        
        # Store for debug
        # print(f"GT: Mean={mean_original:.4f}, SD={sd_original:.4f}, FiltMean={mean_filtered:.4f}, Excl={excluded_count}")

    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Verifier calculation error: {str(e)}"}

    # 4. Score: Report Existence and Format (20 pts)
    user_vals = {}
    if task_result.get("report_exists") and task_result.get("report_created_during_task"):
        score += 10
        try:
            with open(report_path, 'r') as f:
                content = f.read()
                # Simple regex parsing
                m_orig_mean = re.search(r"Original Mean:\s*([\d\.]+)", content, re.IGNORECASE)
                m_orig_sd = re.search(r"Original SD:\s*([\d\.]+)", content, re.IGNORECASE)
                m_filt_mean = re.search(r"Filtered Mean:\s*([\d\.]+)", content, re.IGNORECASE)
                m_excl = re.search(r"Excluded Count:\s*(\d+)", content, re.IGNORECASE)
                
                if m_orig_mean: user_vals['orig_mean'] = float(m_orig_mean.group(1))
                if m_orig_sd: user_vals['orig_sd'] = float(m_orig_sd.group(1))
                if m_filt_mean: user_vals['filt_mean'] = float(m_filt_mean.group(1))
                if m_excl: user_vals['excluded'] = int(m_excl.group(1))
                
                if len(user_vals) == 4:
                    score += 10
                    feedback.append("Report format correct.")
                else:
                    feedback.append("Report missing some required fields.")
        except Exception:
            feedback.append("Failed to parse report.")
    else:
        feedback.append("Report file not found or created before task start.")

    # 5. Score: Accuracy of Reported Values (50 pts)
    # Tolerances: Mean/SD ±0.1 (to account for rounding errors in manual entry), Count ±1
    
    # Original Mean (10 pts)
    if 'orig_mean' in user_vals:
        if abs(user_vals['orig_mean'] - mean_original) < 0.2:
            score += 10
        else:
            feedback.append(f"Original Mean incorrect (Expected ~{mean_original:.2f}, Got {user_vals['orig_mean']})")

    # Original SD (10 pts)
    if 'orig_sd' in user_vals:
        if abs(user_vals['orig_sd'] - sd_original) < 0.2:
            score += 10
        else:
            feedback.append(f"Original SD incorrect (Expected ~{sd_original:.2f}, Got {user_vals['orig_sd']})")

    # Filtered Mean (15 pts) - This proves they actually filtered correctly
    if 'filt_mean' in user_vals:
        if abs(user_vals['filt_mean'] - mean_filtered) < 0.3:
            score += 15
        else:
            feedback.append(f"Filtered Mean incorrect (Expected ~{mean_filtered:.2f}, Got {user_vals['filt_mean']})")

    # Excluded Count (15 pts)
    if 'excluded' in user_vals:
        if abs(user_vals['excluded'] - excluded_count) <= 2:
            score += 15
        else:
            feedback.append(f"Excluded Count incorrect (Expected {excluded_count}, Got {user_vals['excluded']})")

    # 6. Score: Jamovi Project File (20 pts)
    # Check if .omv exists and is a valid zip (omv is essentially a zip)
    if task_result.get("omv_exists") and task_result.get("omv_created_during_task"):
        import zipfile
        if zipfile.is_zipfile(omv_path):
            score += 20
            feedback.append("Jamovi project saved successfully.")
        else:
            feedback.append("Jamovi project file exists but is corrupted.")
    else:
        feedback.append("Jamovi project file not saved.")

    # 7. Score: App Running (10 pts)
    if task_result.get("app_running"):
        score += 10
    else:
        feedback.append("Jamovi was closed before verification.")

    # Final Evaluation
    # Threshold: 70 points. Must have accurate filtered mean to pass.
    key_criterion = False
    if 'filt_mean' in user_vals and abs(user_vals['filt_mean'] - mean_filtered) < 0.3:
        key_criterion = True
    
    passed = (score >= 70) and key_criterion
    
    if passed:
        feedback.insert(0, "Task Passed!")
    else:
        feedback.insert(0, "Task Failed.")

    # Cleanup
    import shutil
    shutil.rmtree(temp_dir)

    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }