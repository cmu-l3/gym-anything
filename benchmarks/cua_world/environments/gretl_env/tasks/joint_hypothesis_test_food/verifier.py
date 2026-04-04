#!/usr/bin/env python3
"""
Verifier for Joint Hypothesis Testing in Gretl.

Verifies that the agent:
1. Created the output file.
2. Performed a restriction test (F-test).
3. Found the correct F-statistic and p-value matching the ground truth.
"""

import json
import os
import re
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def parse_gretl_test_output(content):
    """
    Parses Gretl restriction test output for F-statistic and p-value.
    
    Example Gretl Output:
    Restriction:
      b[const] = 80
      b[income] = 10
    
    Test statistic: F(2, 38) = 0.123594
    with p-value = P(F(2, 38) > 0.123594) = 0.884111
    """
    results = {
        "f_stat": None,
        "p_value": None,
        "is_restriction_test": False
    }
    
    # Check if it looks like a restriction test
    if "Restriction:" in content or "Test statistic: F" in content:
        results["is_restriction_test"] = True
        
    # Regex for F-statistic
    # Pattern: Test statistic: F(df1, df2) = 1.2345
    f_match = re.search(r"Test statistic:\s*F\s*\(\d+,\s*\d+\)\s*=\s*([\d\.]+)", content)
    if f_match:
        try:
            results["f_stat"] = float(f_match.group(1))
        except ValueError:
            pass
            
    # Regex for p-value
    # Pattern: p-value = ... = 0.1234
    # Or simple: p-value = 0.1234
    p_match = re.search(r"p-value\s*=?\s*.*=\s*([\d\.]+)", content)
    if not p_match:
        # Try simpler pattern
        p_match = re.search(r"p-value\s*=\s*([\d\.]+)", content)
        
    if p_match:
        try:
            results["p_value"] = float(p_match.group(1))
        except ValueError:
            pass
            
    return results

def verify_joint_hypothesis_test(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System Error: Copy function not available"}

    # 1. Retrieve Result JSON
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result_data = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve task results: {str(e)}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)
            
    output_exists = result_data.get("output_exists", False)
    file_created_during_task = result_data.get("file_created_during_task", False)
    output_path = result_data.get("output_file_path", "")
    ground_truth_path = result_data.get("ground_truth_path", "")
    
    score = 0
    feedback = []
    
    # Criterion 1: File Existence & Creation (20 pts)
    if not output_exists:
        return {"passed": False, "score": 0, "feedback": "Output file not found."}
    
    if file_created_during_task:
        score += 20
        feedback.append("Output file created during task.")
    else:
        feedback.append("Output file exists but has old timestamp (pre-existing?).")
        # Continue but with penalty
    
    # Retrieve User Output
    user_content = ""
    temp_user_file = tempfile.NamedTemporaryFile(delete=False, suffix='.txt')
    try:
        copy_from_env(output_path, temp_user_file.name)
        with open(temp_user_file.name, 'r', encoding='utf-8', errors='ignore') as f:
            user_content = f.read()
    except Exception as e:
        return {"passed": False, "score": score, "feedback": f"Could not read output file: {str(e)}"}
    finally:
        if os.path.exists(temp_user_file.name):
            os.unlink(temp_user_file.name)
            
    # Retrieve Ground Truth
    gt_content = ""
    temp_gt_file = tempfile.NamedTemporaryFile(delete=False, suffix='.txt')
    try:
        copy_from_env(ground_truth_path, temp_gt_file.name)
        with open(temp_gt_file.name, 'r', encoding='utf-8', errors='ignore') as f:
            gt_content = f.read()
    except Exception as e:
        # Fallback if ground truth file missing (should not happen with proper setup)
        logger.error(f"Missing ground truth file: {e}")
        gt_content = "Test statistic: F(2, 38) = 0.123594\np-value = 0.884111" 
    finally:
        if os.path.exists(temp_gt_file.name):
            os.unlink(temp_gt_file.name)

    # Parse Both
    user_results = parse_gretl_test_output(user_content)
    gt_results = parse_gretl_test_output(gt_content)
    
    # Criterion 2: Content Validity (20 pts)
    if user_results["is_restriction_test"]:
        score += 20
        feedback.append("File contains valid restriction test output.")
    else:
        return {"passed": False, "score": score, "feedback": "Output file does not look like a Gretl restriction test result."}
        
    # Criterion 3: Numerical Accuracy (60 pts total)
    # F-Statistic (30 pts)
    f_stat_ok = False
    if user_results["f_stat"] is not None and gt_results["f_stat"] is not None:
        if abs(user_results["f_stat"] - gt_results["f_stat"]) < 0.05:
            score += 30
            f_stat_ok = True
            feedback.append(f"F-statistic matches (Expected: {gt_results['f_stat']:.4f}, Found: {user_results['f_stat']:.4f}).")
        else:
            feedback.append(f"F-statistic incorrect (Expected: {gt_results['f_stat']:.4f}, Found: {user_results['f_stat']:.4f}).")
    elif user_results["f_stat"] is None:
        feedback.append("Could not parse F-statistic from output.")

    # P-Value (30 pts)
    p_val_ok = False
    if user_results["p_value"] is not None and gt_results["p_value"] is not None:
        if abs(user_results["p_value"] - gt_results["p_value"]) < 0.01:
            score += 30
            p_val_ok = True
            feedback.append(f"P-value matches (Expected: {gt_results['p_value']:.4f}, Found: {user_results['p_value']:.4f}).")
        else:
            feedback.append(f"P-value incorrect (Expected: {gt_results['p_value']:.4f}, Found: {user_results['p_value']:.4f}).")
    elif user_results["p_value"] is None:
        feedback.append("Could not parse p-value from output.")
        
    # Final Decision
    passed = (score >= 70) and f_stat_ok and p_val_ok
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }