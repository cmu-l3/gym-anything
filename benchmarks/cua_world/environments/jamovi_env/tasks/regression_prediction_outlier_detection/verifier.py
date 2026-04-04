#!/usr/bin/env python3
import json
import os
import tempfile
import zipfile
import pandas as pd
import numpy as np
import statsmodels.api as sm

def verify_regression_prediction_outlier_detection(traj, env_info, task_info):
    """
    Verifies that the agent performed regression, saved predictions/residuals,
    and correctly identified the outlier.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load result metadata
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result_data = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load task result: {e}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    score = 0
    feedback_lines = []
    
    # Check 1: OMV File Existence & Modification (20 pts)
    omv_exists = result_data.get('omv_exists', False)
    omv_created = result_data.get('omv_created_during_task', False)
    
    if omv_exists and omv_created:
        score += 20
        feedback_lines.append("Project file (.omv) saved successfully.")
    elif omv_exists:
        score += 10
        feedback_lines.append("Project file exists but timestamp check failed.")
    else:
        feedback_lines.append("Project file (.omv) not found.")

    # Check 2: Report File Existence (10 pts)
    report_exists = result_data.get('report_exists', False)
    if report_exists:
        score += 10
        feedback_lines.append("Report file found.")
    else:
        feedback_lines.append("Report file not found.")

    # Prepare Ground Truth
    # We need to replicate the analysis to check values
    temp_csv = tempfile.NamedTemporaryFile(delete=False, suffix='.csv')
    try:
        # Copy dataset from env to calculate ground truth
        dataset_path = result_data.get('dataset_path', '/home/ga/Documents/Jamovi/ExamAnxiety.csv')
        copy_from_env(dataset_path, temp_csv.name)
        
        df = pd.read_csv(temp_csv.name)
        
        # Ground Truth Regression: Exam ~ Revise + Anxiety
        X = df[['Revise', 'Anxiety']]
        X = sm.add_constant(X)
        y = df['Exam']
        
        model = sm.OLS(y, X).fit()
        df['Predicted'] = model.predict(X)
        df['Residuals'] = df['Exam'] - df['Predicted']
        
        # Identify Max Positive Residual Outlier
        outlier_row = df.loc[df['Residuals'].idxmax()]
        gt_code = str(outlier_row['Code'])
        gt_resid = outlier_row['Residuals']
        gt_pred = outlier_row['Predicted']
        gt_actual = outlier_row['Exam']
        
    except Exception as e:
        if os.path.exists(temp_csv.name):
            os.unlink(temp_csv.name)
        return {"passed": False, "score": score, "feedback": f"Ground truth calculation failed: {e}"}
    finally:
        if os.path.exists(temp_csv.name):
            os.unlink(temp_csv.name)

    # Check 3: OMV Content Inspection (Evidence of Saved Variables) (20 pts)
    # Jamovi .omv is a zip file. We check metadata for new variables.
    if omv_exists:
        temp_omv = tempfile.NamedTemporaryFile(delete=False, suffix='.omv')
        try:
            copy_from_env(result_data['omv_path'], temp_omv.name)
            
            with zipfile.ZipFile(temp_omv.name, 'r') as z:
                # Check metadata.json for variable definitions
                # We look for variables that likely correspond to Predicted/Residuals
                # Jamovi often names them "Predicted" or "Residuals" or "Exam (Predicted)"
                meta_content = ""
                if 'metadata.json' in z.namelist():
                    meta_content = z.read('metadata.json').decode('utf-8')
                elif '01.json' in z.namelist(): # Sometimes analyses are stored in numbered jsons
                    meta_content = z.read('01.json').decode('utf-8')
                
                # Loose check for existence of residual/predicted keywords in the zip structure
                # This is safer than parsing complex JSON schemas which might vary
                found_resid = False
                found_pred = False
                
                # Check file list for data columns if stored separately or check json content
                # Inspecting metadata.json usually reveals the "fields" list
                if 'Residual' in meta_content or 'residual' in meta_content:
                    found_resid = True
                if 'Predicted' in meta_content or 'predicted' in meta_content:
                    found_pred = True
                
                if found_resid and found_pred:
                    score += 20
                    feedback_lines.append("OMV file contains Predictor/Residual variables.")
                elif found_resid or found_pred:
                    score += 10
                    feedback_lines.append("OMV file contains some generated variables.")
                else:
                    feedback_lines.append("Could not confirm Predicted/Residual columns in OMV file.")
                    
        except Exception as e:
            feedback_lines.append(f"Failed to inspect OMV file: {e}")
        finally:
            if os.path.exists(temp_omv.name):
                os.unlink(temp_omv.name)

    # Check 4: Report Content Accuracy (50 pts total)
    if report_exists:
        temp_report = tempfile.NamedTemporaryFile(delete=False, suffix='.txt')
        try:
            copy_from_env(result_data['report_path'], temp_report.name)
            with open(temp_report.name, 'r') as f:
                report_content = f.read()
            
            # Parse report
            # Expected format: Key: Value
            report_data = {}
            for line in report_content.splitlines():
                if ':' in line:
                    key, val = line.split(':', 1)
                    report_data[key.strip()] = val.strip()
            
            # Check Student Code (25 pts)
            report_code = report_data.get('Student_Code', '')
            if str(report_code) == str(gt_code):
                score += 25
                feedback_lines.append(f"Correct outlier student identified: {gt_code}")
            else:
                feedback_lines.append(f"Incorrect student code. Expected {gt_code}, got {report_code}")

            # Check Values (25 pts)
            try:
                rep_resid = float(report_data.get('Residual', 0))
                rep_pred = float(report_data.get('Predicted_Exam', 0))
                
                # Tolerances
                resid_ok = abs(rep_resid - gt_resid) < 0.5
                pred_ok = abs(rep_pred - gt_pred) < 0.5
                
                if resid_ok and pred_ok:
                    score += 25
                    feedback_lines.append("Reported Residual and Predicted values are accurate.")
                elif resid_ok or pred_ok:
                    score += 10
                    feedback_lines.append("Some reported values are inaccurate.")
                else:
                    feedback_lines.append(f"Reported values inaccurate. Expected Resid~{gt_resid:.2f}, got {rep_resid}")
            except ValueError:
                feedback_lines.append("Could not parse numeric values from report.")

        except Exception as e:
            feedback_lines.append(f"Failed to verify report content: {e}")
        finally:
            if os.path.exists(temp_report.name):
                os.unlink(temp_report.name)

    # Final logic
    passed = score >= 75
    
    return {
        "passed": passed,
        "score": score,
        "feedback": "\n".join(feedback_lines)
    }