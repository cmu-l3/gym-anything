#!/usr/bin/env python3
import json
import os
import re
import tempfile
import logging
import sys

# Configure logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger("verifier")

def verify_normality_check_insectsprays(traj, env_info, task_info):
    """
    Verifies that the agent performed the normality check correctly and chose the right test.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System Error: Copy function not available"}

    # 1. Retrieve result JSON
    temp_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_json.name)
        with open(temp_json.name, 'r') as f:
            result_data = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve task result: {str(e)}"}
    finally:
        if os.path.exists(temp_json.name):
            os.unlink(temp_json.name)

    # 2. Check file existence
    report_exists = result_data.get('report_exists', False)
    omv_exists = result_data.get('omv_exists', False)
    
    if not report_exists:
        return {"passed": False, "score": 0, "feedback": "Analysis report file not found."}

    # 3. Retrieve the dataset to compute ground truth
    dataset_path = result_data.get('dataset_path', '/home/ga/Documents/Jamovi/InsectSprays.csv')
    temp_csv = tempfile.NamedTemporaryFile(delete=False, suffix='.csv')
    try:
        copy_from_env(dataset_path, temp_csv.name)
        
        # Calculate Ground Truth using Python
        # We need pandas and scipy
        try:
            import pandas as pd
            from scipy import stats
            
            df = pd.read_csv(temp_csv.name)
            
            # Filter for groups A and F
            group_a = df[df['spray'] == 'A']['count']
            group_f = df[df['spray'] == 'F']['count']
            
            # Shapiro-Wilk
            sw_a = stats.shapiro(group_a)
            sw_f = stats.shapiro(group_f)
            
            p_a_gt = sw_a.pvalue
            p_f_gt = sw_f.pvalue
            
            # Decision Rule: if p < 0.05 for EITHER, use Mann-Whitney
            is_non_normal = (p_a_gt < 0.05) or (p_f_gt < 0.05)
            expected_test = "Mann-Whitney" if is_non_normal else "T-Test"
            
            # Calculate final test statistic
            if expected_test == "Mann-Whitney":
                mwu_res = stats.mannwhitneyu(group_a, group_f, alternative='two-sided')
                final_p_gt = mwu_res.pvalue
            else:
                ttest_res = stats.ttest_ind(group_a, group_f, equal_var=True) # Assuming Student's
                final_p_gt = ttest_res.pvalue
                
        except ImportError:
            return {"passed": False, "score": 0, "feedback": "Verifier environment missing required libraries (pandas/scipy)."}
        except Exception as e:
            return {"passed": False, "score": 0, "feedback": f"Error calculating ground truth: {str(e)}"}
            
    finally:
        if os.path.exists(temp_csv.name):
            os.unlink(temp_csv.name)

    # 4. Retrieve and Parse the User Report
    report_path = result_data.get('report_path')
    temp_report = tempfile.NamedTemporaryFile(delete=False, suffix='.txt')
    try:
        copy_from_env(report_path, temp_report.name)
        with open(temp_report.name, 'r') as f:
            report_content = f.read()
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read report file: {str(e)}"}
    finally:
        if os.path.exists(temp_report.name):
            os.unlink(temp_report.name)

    # Scoring Logic
    score = 0
    feedback = []
    
    # Check SW P-values
    # Regex to find numbers. We expect format roughly: "Spray A Shapiro-Wilk p: <value>"
    # We'll look for lines containing "Spray A" and a float, and "Spray F" and a float.
    
    # Helper to find float in a line
    def extract_p(text, label):
        match = re.search(rf"{label}.*?(\d*\.\d+)", text, re.IGNORECASE)
        if match:
            return float(match.group(1))
        return None

    p_a_agent = extract_p(report_content, "Spray A")
    p_f_agent = extract_p(report_content, "Spray F")
    
    # Score Normality Values (30 pts)
    normality_score = 0
    if p_a_agent is not None and abs(p_a_agent - p_a_gt) < 0.01:
        normality_score += 15
    else:
        feedback.append(f"Spray A p-value incorrect or not found. Expected ~{p_a_gt:.4f}, got {p_a_agent}")
        
    if p_f_agent is not None and abs(p_f_agent - p_f_gt) < 0.01:
        normality_score += 15
    else:
        feedback.append(f"Spray F p-value incorrect or not found. Expected ~{p_f_gt:.4f}, got {p_f_agent}")
    
    score += normality_score

    # Score Decision (30 pts)
    decision_score = 0
    # Check if report contains the correct test name
    if expected_test.lower() in report_content.lower() or \
       (expected_test == "Mann-Whitney" and ("mann" in report_content.lower() or "whitney" in report_content.lower())) or \
       (expected_test == "T-Test" and "t-test" in report_content.lower()):
        decision_score = 30
    else:
        feedback.append(f"Incorrect test selected. Based on normality, expected {expected_test}.")
    
    score += decision_score

    # Score Final Result (30 pts)
    # Look for final p-value
    result_score = 0
    # We look for a p-value that is close to the ground truth for the *correct* test.
    # If the agent ran the wrong test, they likely won't match this value, which is correct (double penalty appropriate here as per task rigor).
    # Find any float that matches the final p-value
    
    # Simple search for the final p-value anywhere in the text
    # We define a wider tolerance since different implementations (exact vs asymptotic) might vary slightly
    found_final_p = False
    floats = [float(x) for x in re.findall(r"0\.\d+|1\.00", report_content)]
    for f in floats:
        # Avoid matching the SW p-values if they are distinct
        if abs(f - final_p_gt) < 0.01:
             found_final_p = True
             break
    
    if found_final_p:
        result_score = 30
    else:
        feedback.append(f"Final test p-value incorrect. Expected ~{final_p_gt:.4f}")
    
    score += result_score

    # Artifacts (10 pts)
    if omv_exists and result_data.get('omv_created_during_task'):
        score += 10
    elif omv_exists:
        score += 5
        feedback.append("OMV file exists but timestamp suggests it wasn't created during task.")
    else:
        feedback.append("Analysis .omv file not found.")

    passed = (score >= 70) and (normality_score >= 15) and (decision_score == 30)

    return {
        "passed": passed,
        "score": score,
        "feedback": "; ".join(feedback) if feedback else "Perfect execution."
    }