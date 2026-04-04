#!/usr/bin/env python3
import json
import os
import tempfile
import zipfile
import base64
import pandas as pd
import numpy as np
import statsmodels.api as sm

def verify_nonlinear_age_conscientiousness(traj, env_info, task_info):
    """
    Verifies the non-linear age effects task.
    
    Criteria:
    1. OMV file exists and was created during task.
    2. OMV file is a valid zip (Jamovi format).
    3. Results text file exists and contains correct R2 change and p-value.
    4. Anti-gaming: File timestamps.
    """
    
    # 1. Setup and Load Results
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}
    
    # Load task result JSON
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result JSON: {str(e)}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)
            
    score = 0
    feedback = []
    
    # 2. Check OMV File (30 points)
    if result.get('omv_exists') and result.get('omv_created_during_task'):
        score += 30
        feedback.append("Jamovi project file created.")
        
        # Verify it's a valid zip (basic validity check)
        temp_omv = tempfile.NamedTemporaryFile(delete=False, suffix='.omv')
        try:
            copy_from_env("/home/ga/Documents/Jamovi/Conscientiousness_NonLinear.omv", temp_omv.name)
            if zipfile.is_zipfile(temp_omv.name):
                score += 10
                feedback.append("Project file is valid.")
            else:
                feedback.append("Project file is corrupted or not a valid OMV archive.")
        except:
            feedback.append("Could not retrieve OMV file for validation.")
        finally:
            if os.path.exists(temp_omv.name):
                os.unlink(temp_omv.name)
    else:
        feedback.append("Jamovi project file missing or not created during task.")

    # 3. Calculate Ground Truth (Robust verification)
    # We need the source data to calculate the expected values
    temp_data = tempfile.NamedTemporaryFile(delete=False, suffix='.csv')
    try:
        # Try to copy source data from env to ensure we use exact same data
        copy_from_env("/home/ga/Documents/Jamovi/BFI25.csv", temp_data.name)
        df = pd.read_csv(temp_data.name)
        
        # Replicate Agent's Expected Workflow
        # 1. Compute C_Score (Mean of C1-C5)
        c_items = ['C1', 'C2', 'C3', 'C4', 'C5']
        # Jamovi row-wise mean usually handles NaNs by skipping them if configured, 
        # but BFI25.csv in this env is cleaned of NaNs.
        df['C_Score'] = df[c_items].mean(axis=1)
        
        # 2. Compute Age_Sq
        df['Age_Sq'] = df['age'] ** 2
        
        # 3. Hierarchical Regression
        # Model 1: C_Score ~ Age
        X1 = df[['age']]
        X1 = sm.add_constant(X1)
        y = df['C_Score']
        model1 = sm.OLS(y, X1).fit()
        r2_1 = model1.rsquared
        
        # Model 2: C_Score ~ Age + Age_Sq
        X2 = df[['age', 'Age_Sq']]
        X2 = sm.add_constant(X2)
        model2 = sm.OLS(y, X2).fit()
        r2_2 = model2.rsquared
        
        # Calculate R2 Change
        r2_change_gt = r2_2 - r2_1
        
        # Calculate p-value for the change (F-test)
        # Compare Model 1 (restricted) vs Model 2 (unrestricted)
        f_test = model2.compare_f_test(model1)
        p_value_gt = f_test[1]
        
    except Exception as e:
        return {"passed": False, "score": score, "feedback": f"Verifier failed to calculate ground truth: {str(e)}"}
    finally:
        if os.path.exists(temp_data.name):
            os.unlink(temp_data.name)

    # 4. Check Results Text File (60 points)
    if result.get('txt_exists') and result.get('txt_created_during_task'):
        try:
            content = base64.b64decode(result.get('txt_content_base64', '')).decode('utf-8')
            
            # Parse user values
            user_r2 = None
            user_p = None
            
            for line in content.split('\n'):
                if 'R2_Change:' in line:
                    try:
                        user_r2 = float(line.split(':')[1].strip())
                    except: pass
                if 'p_value:' in line:
                    try:
                        user_p = float(line.split(':')[1].strip())
                        # Handle "< .001" notation if agent wrote that
                        if '<' in line.split(':')[1]:
                            user_p = 0.0001 # Treat as small
                    except: pass
            
            # Verify R2 Change
            if user_r2 is not None:
                # Tolerance: +/- 0.002
                if abs(user_r2 - r2_change_gt) < 0.002:
                    score += 30
                    feedback.append(f"R² Change correct (User: {user_r2}, GT: {r2_change_gt:.4f}).")
                else:
                    feedback.append(f"R² Change incorrect (User: {user_r2}, GT: {r2_change_gt:.4f}).")
            else:
                feedback.append("Could not parse R2_Change from text file.")

            # Verify p-value
            if user_p is not None:
                # If GT is very small, user might write 0.000 or <.001
                if p_value_gt < 0.001:
                    if user_p < 0.002:
                        score += 30
                        feedback.append("p-value correct (Significant).")
                    else:
                        feedback.append(f"p-value incorrect (User: {user_p}, GT: {p_value_gt:.4f}).")
                else:
                    if abs(user_p - p_value_gt) < 0.05:
                        score += 30
                        feedback.append(f"p-value correct (User: {user_p}, GT: {p_value_gt:.4f}).")
                    else:
                        feedback.append(f"p-value incorrect (User: {user_p}, GT: {p_value_gt:.4f}).")
            else:
                # Check for "p < .001" string if parsing failed
                if p_value_gt < 0.001 and '<' in content and ('.001' in content or '0.001' in content):
                    score += 30
                    feedback.append("p-value notation correct.")
                else:
                    feedback.append("Could not parse p_value from text file.")
                    
        except Exception as e:
            feedback.append(f"Error parsing result file: {str(e)}")
    else:
        feedback.append("Results text file missing.")

    # Final Pass Determination
    passed = score >= 80
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }