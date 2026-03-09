#!/usr/bin/env python3
import json
import os
import tempfile
import zipfile
import re
import pandas as pd
import numpy as np
import statsmodels.api as sm
import statsmodels.formula.api as smf

def verify_composite_score_regression_bfi(traj, env_info, task_info):
    """
    Verifies the Jamovi composite score and regression task.
    1. Checks if the .omv file exists and was created during the task.
    2. Checks if the report text file exists and contains correct values.
    3. Calculates ground truth values from the raw CSV using Python.
    4. Inspects the .omv file (zip structure) to verify variable creation and analysis config.
    """
    
    # 1. Setup and Environment Access
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    dataset_path = metadata.get('dataset_path', '/home/ga/Documents/Jamovi/BFI25.csv')
    
    score = 0
    feedback = []
    
    # Load task result JSON
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            task_result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load task result: {str(e)}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    # 2. Verify File Existence & Anti-Gaming (Timestamp)
    omv_exists = task_result.get('omv_exists', False)
    omv_fresh = task_result.get('omv_created_during_task', False)
    report_exists = task_result.get('report_exists', False)
    report_fresh = task_result.get('report_created_during_task', False)
    
    if omv_exists and omv_fresh:
        score += 10
        feedback.append("Project file (.omv) saved successfully.")
    else:
        feedback.append("Project file (.omv) missing or not saved during task.")

    if report_exists and report_fresh:
        score += 10
        feedback.append("Report file (.txt) saved successfully.")
    else:
        feedback.append("Report file (.txt) missing or not saved during task.")

    # 3. Ground Truth Calculation
    # We need to replicate the analysis to get the correct numbers
    try:
        # Copy the original dataset from container to calculate ground truth
        temp_csv = tempfile.NamedTemporaryFile(delete=False, suffix='.csv')
        copy_from_env(dataset_path, temp_csv.name)
        
        df = pd.read_csv(temp_csv.name)
        
        # Ground Truth Step 1: Compute Neuroticism_Mean
        # Items N1-N5 are columns. Ensure they are numeric.
        n_cols = ['N1', 'N2', 'N3', 'N4', 'N5']
        # Drop rows with missing values in these cols if any (Jamovi default behavior is listwise deletion for analysis)
        df_clean = df.dropna(subset=n_cols + ['age', 'gender'])
        
        df_clean['Neuroticism_Mean'] = df_clean[n_cols].mean(axis=1)
        
        # Ground Truth Step 2: Linear Regression
        # Neuroticism_Mean ~ age + C(gender)
        # Jamovi uses 'age' as covariate (continuous) and 'gender' as factor.
        # Note: 'gender' in BFI dataset is usually 1=Male, 2=Female.
        
        model = smf.ols("Neuroticism_Mean ~ age + C(gender)", data=df_clean).fit()
        
        # Extract Age statistics
        age_coeff = model.params['age']
        conf_int = model.conf_int(alpha=0.05)
        age_lower = conf_int.loc['age', 0]
        age_upper = conf_int.loc['age', 1]
        
        os.unlink(temp_csv.name)
        
    except Exception as e:
        return {"passed": False, "score": score, "feedback": f"Verifier error calculating ground truth: {str(e)}"}

    # 4. Verify Reported Values
    if report_exists:
        try:
            temp_report = tempfile.NamedTemporaryFile(delete=False, suffix='.txt')
            copy_from_env(metadata.get('report_path'), temp_report.name)
            with open(temp_report.name, 'r') as f:
                content = f.read()
            os.unlink(temp_report.name)
            
            # Extract numbers from text using regex
            numbers = re.findall(r"[-+]?\d*\.\d+|\d+", content)
            
            # We expect at least 3 numbers: Coeff, Lower, Upper
            # We will check if the ground truth values appear in the text with some tolerance
            tolerance = 0.005
            
            found_coeff = any(abs(float(n) - age_coeff) < tolerance for n in numbers)
            found_lower = any(abs(float(n) - age_lower) < tolerance for n in numbers)
            found_upper = any(abs(float(n) - age_upper) < tolerance for n in numbers)
            
            if found_coeff:
                score += 15
                feedback.append(f"Correct Age coefficient found (expected ~{age_coeff:.4f}).")
            else:
                feedback.append(f"Age coefficient incorrect or not found (expected ~{age_coeff:.4f}).")
                
            if found_lower and found_upper:
                score += 15
                feedback.append(f"Correct Confidence Intervals found (expected [{age_lower:.4f}, {age_upper:.4f}]).")
            elif found_lower or found_upper:
                score += 7
                feedback.append("Partially correct Confidence Intervals.")
            else:
                feedback.append(f"Confidence Intervals incorrect (expected [{age_lower:.4f}, {age_upper:.4f}]).")
                
        except Exception as e:
            feedback.append(f"Error parsing report file: {str(e)}")

    # 5. Inspect OMV File Structure (Advanced Verification)
    if omv_exists:
        try:
            temp_omv = tempfile.NamedTemporaryFile(delete=False, suffix='.omv')
            copy_from_env(metadata.get('project_path'), temp_omv.name)
            
            is_valid_omv = False
            has_computed_var = False
            has_regression = False
            
            if zipfile.is_zipfile(temp_omv.name):
                with zipfile.ZipFile(temp_omv.name, 'r') as z:
                    # Check Manifest or Meta
                    file_list = z.namelist()
                    if 'meta' in file_list:
                        is_valid_omv = True
                        
                        # Check for Computed Variable in metadata
                        # The metadata structure varies, but usually defines vars
                        meta_data = json.loads(z.read('meta').decode('utf-8'))
                        # This is a heuristic; actual OMV structure is complex.
                        # We check if 'Neuroticism_Mean' appears in the binary xdata or metadata strings
                        # A safer check is looking for the analysis syntax or history
                        
                        # Check 'index' or 'analysis' entry if available (Jamovi specific)
                        # Often Jamovi stores analyses in separate numbered folders like '01 linear', '02 ...'
                        # We look for an analysis file that mentions 'linReg'
                        
                        for filename in file_list:
                            if filename.endswith('analysis'):
                                try:
                                    analysis_json = json.loads(z.read(filename).decode('utf-8'))
                                    # Check for Linear Regression
                                    if analysis_json.get('name') == 'linReg':
                                        options = analysis_json.get('options', {})
                                        # Check configuration
                                        if options.get('dep') == 'Neuroticism_Mean' and \
                                           'age' in options.get('covs', []) and \
                                           'gender' in options.get('factors', []) and \
                                           options.get('ci', False) == True:
                                            has_regression = True
                                except:
                                    pass

                        # Heuristic for computed variable: check if it's in the data definition
                        # or if the variable name exists in the dataset schema
                        # We'll just check if the string "Neuroticism_Mean" is in the meta file
                        if "Neuroticism_Mean" in str(meta_data):
                            has_computed_var = True
            
            if is_valid_omv:
                score += 10
                feedback.append("Valid OMV file structure.")
            
            if has_computed_var:
                score += 25
                feedback.append("Computed variable 'Neuroticism_Mean' detected in project.")
            else:
                feedback.append("Could not confirm 'Neuroticism_Mean' variable in project metadata.")
                
            if has_regression:
                score += 15
                feedback.append("Linear Regression correctly configured in project.")
            else:
                # If we couldn't parse it perfectly but numbers were right, we might still give points
                # But here we strictly check configuration if possible.
                feedback.append("Linear Regression configuration not fully verified in project metadata (check variable names).")

            os.unlink(temp_omv.name)
            
        except Exception as e:
            feedback.append(f"Error inspecting OMV file: {str(e)}")

    # Final Score Calculation
    passed = score >= 70
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }