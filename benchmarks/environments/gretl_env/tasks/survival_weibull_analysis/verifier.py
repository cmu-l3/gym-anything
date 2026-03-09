#!/usr/bin/env python3
import json
import os
import tempfile
import re

def verify_survival_weibull_analysis(traj, env_info, task_info):
    """
    Verifies the Survival Analysis task.
    
    Criteria:
    1. Script file exists (20 pts)
    2. Script contains correct commands (weibull) (20 pts)
    3. Report file exists and contains values (20 pts)
    4. Values match ground truth (Coef & Sigma) (20 pts)
    5. Hazard shape interpretation matches Sigma (20 pts)
    """
    
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    score = 0
    feedback = []
    
    # Helper to copy file content
    def get_file_content(remote_path):
        if not remote_path: return None
        local_tf = tempfile.NamedTemporaryFile(delete=False)
        local_tf.close()
        try:
            copy_from_env(remote_path, local_tf.name)
            with open(local_tf.name, 'r') as f:
                return f.read()
        except Exception:
            return None
        finally:
            if os.path.exists(local_tf.name):
                os.unlink(local_tf.name)

    # 1. Get Result JSON
    task_result_content = get_file_content("/tmp/task_result.json")
    if not task_result_content:
        return {"passed": False, "score": 0, "feedback": "Failed to retrieve task results"}
    
    result = json.loads(task_result_content)
    
    # 2. Check Files Existence
    if result.get("script_exists"):
        score += 20
        feedback.append("Script file created.")
    else:
        feedback.append("Script file missing.")

    if result.get("report_exists") and result.get("file_created_during_task"):
        score += 20
        feedback.append("Report file created.")
    else:
        feedback.append("Report file missing or not created during task.")

    # 3. Analyze Content
    user_script = get_file_content(result.get("user_script_path"))
    user_report = get_file_content(result.get("user_report_path"))
    ground_truth_json = get_file_content(result.get("ground_truth_path"))
    
    ground_truth = {}
    if ground_truth_json:
        try:
            ground_truth = json.loads(ground_truth_json)
        except:
            pass

    # Check Script Content
    if user_script:
        if "--weibull" in user_script.lower():
            score += 20
            feedback.append("Script uses Weibull estimation.")
        elif "duration" in user_script.lower() and "distribution=weibull" in user_script.lower():
             score += 20
             feedback.append("Script uses Weibull estimation (alternative syntax).")
        else:
            feedback.append("Script does not appear to use Weibull estimation.")

    # Check Report Values
    if user_report and ground_truth:
        # Parse user report
        # Expected format: Key: Value
        prod_coeff_match = re.search(r"Prod_Coefficient:\s*([-\d\.]+)", user_report, re.IGNORECASE)
        sigma_match = re.search(r"Sigma:\s*([-\d\.]+)", user_report, re.IGNORECASE)
        shape_match = re.search(r"Hazard_Shape:\s*(\w+)", user_report, re.IGNORECASE)
        
        user_prod = float(prod_coeff_match.group(1)) if prod_coeff_match else None
        user_sigma = float(sigma_match.group(1)) if sigma_match else None
        user_shape = shape_match.group(1) if shape_match else None
        
        gt_prod = ground_truth.get("prod_coeff")
        gt_sigma = ground_truth.get("sigma")
        gt_shape = ground_truth.get("hazard_shape")

        # Compare Values (Tolerance 5%)
        val_score = 0
        if user_prod is not None and gt_prod is not None:
            if abs(user_prod - gt_prod) < 0.05 * abs(gt_prod):
                val_score += 10
                feedback.append(f"Production coefficient correct ({user_prod}).")
            else:
                feedback.append(f"Production coefficient incorrect (Expected {gt_prod}, Got {user_prod}).")
        
        if user_sigma is not None and gt_sigma is not None:
            if abs(user_sigma - gt_sigma) < 0.05 * abs(gt_sigma):
                val_score += 10
                feedback.append(f"Sigma correct ({user_sigma}).")
            else:
                feedback.append(f"Sigma incorrect (Expected {gt_sigma}, Got {user_sigma}).")
        
        score += val_score

        # Check Interpretation
        # If they got the sigma wrong but interpretation matches their sigma, that's partial credit in some rubrics,
        # but here we require correct analysis.
        # Actually, let's verify interpretation against GROUND TRUTH first, 
        # but if sigma was slightly off, check consistency.
        
        # Rigorous check: Interpretation must match Truth
        if user_shape and gt_shape:
            if user_shape.lower() == gt_shape.lower():
                score += 20
                feedback.append(f"Hazard shape interpretation correct ({user_shape}).")
            else:
                feedback.append(f"Hazard shape interpretation incorrect (Expected {gt_shape}, Got {user_shape}).")
    elif not ground_truth:
        feedback.append("Error: Could not generate ground truth for comparison.")
    
    passed = score >= 80
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }