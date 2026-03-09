#!/usr/bin/env python3
"""
Verifier for Lasso Regression Task (JASP).
"""

import json
import os
import zipfile
import re
import tempfile
import logging
import shutil

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_lasso_regression_bigfive(traj, env_info, task_info):
    """
    Verifies the JASP Lasso Regression task.
    
    Criteria:
    1. JASP project file (.jasp) exists and was created during the task.
    2. Text report exists and contains reasonable metrics (RMSE, R2).
    3. The .jasp file (which is a zip) contains evidence of Machine Learning/Regression analysis.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    score = 0
    max_score = 100
    feedback_parts = []
    
    # ------------------------------------------------------------------
    # 1. Retrieve Task Result JSON
    # ------------------------------------------------------------------
    temp_result_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_result_json.name)
        with open(temp_result_json.name, 'r') as f:
            task_result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve task result: {str(e)}"}
    finally:
        if os.path.exists(temp_result_json.name):
            os.unlink(temp_result_json.name)

    # ------------------------------------------------------------------
    # 2. Check JASP Project File (Creation & Validity) - 30 pts
    # ------------------------------------------------------------------
    jasp_info = task_result.get('jasp_file', {})
    jasp_exists = jasp_info.get('exists', False)
    jasp_fresh = jasp_info.get('created_during_task', False)
    jasp_path = jasp_info.get('path', '')
    
    if jasp_exists and jasp_fresh:
        score += 30
        feedback_parts.append("JASP project file created successfully.")
        
        # ------------------------------------------------------------------
        # 3. Analyze JASP File Content (Deep Verification) - 30 pts
        # ------------------------------------------------------------------
        # JASP files are ZIP archives. We check internal structure for ML analysis.
        temp_jasp = tempfile.NamedTemporaryFile(delete=False, suffix='.jasp')
        try:
            copy_from_env(jasp_path, temp_jasp.name)
            
            is_valid_jasp = False
            has_ml_analysis = False
            
            if zipfile.is_zipfile(temp_jasp.name):
                with zipfile.ZipFile(temp_jasp.name, 'r') as z:
                    file_list = z.namelist()
                    # Check for typical JASP structure
                    if 'manifest.json' in file_list or any(f.startswith('analysis/') for f in file_list):
                        is_valid_jasp = True
                    
                    # Search for ML/Regression keywords in analysis definitions
                    # Usually found in analysis scripts or results JSONs inside the zip
                    for fname in file_list:
                        if fname.endswith('.json') or fname.endswith('.r') or fname.endswith('index.html'):
                            try:
                                content = z.read(fname).decode('utf-8', errors='ignore')
                                # Look for Machine Learning Regression identifiers
                                if 'Machine Learning' in content or 'mlRegression' in content or 'lasso' in content.lower():
                                    has_ml_analysis = True
                                    break
                            except:
                                continue
            
            if is_valid_jasp:
                score += 10
                feedback_parts.append("File is a valid JASP archive.")
                if has_ml_analysis:
                    score += 20
                    feedback_parts.append("Confirmed Machine Learning/Lasso analysis inside JASP file.")
                else:
                    feedback_parts.append("Could not confirm specific ML analysis in file structure (manual check recommended).")
            else:
                feedback_parts.append("JASP file is not a valid zip archive.")
                
        except Exception as e:
            feedback_parts.append(f"Failed to inspect JASP file content: {str(e)}")
        finally:
            if os.path.exists(temp_jasp.name):
                os.unlink(temp_jasp.name)
                
    elif jasp_exists:
        score += 10
        feedback_parts.append("JASP file exists but was not modified during task (stale?).")
    else:
        feedback_parts.append("JASP project file not found.")

    # ------------------------------------------------------------------
    # 4. Check Report Content (RMSE, R2, Predictors) - 40 pts
    # ------------------------------------------------------------------
    report_info = task_result.get('report_file', {})
    report_exists = report_info.get('exists', False)
    
    if report_exists:
        # Retrieve the actual report file for parsing
        temp_report = tempfile.NamedTemporaryFile(delete=False, suffix='.txt')
        try:
            copy_from_env(report_info.get('path'), temp_report.name)
            with open(temp_report.name, 'r') as f:
                content = f.read().lower()
            
            # Check for RMSE (Root Mean Squared Error)
            if 'rmse' in content or 'root mean squared error' in content:
                score += 10
                feedback_parts.append("Report mentions RMSE.")
                # Basic plausibility check: Look for a number near RMSE keywords
                # Note: Expected RMSE for Neuroticism (scale 1-5 usually) is likely around 0.5-1.5
            
            # Check for R-squared
            if 'r2' in content or 'r-squared' in content or 'r^2' in content:
                score += 10
                feedback_parts.append("Report mentions R-squared.")
            
            # Check for Predictors (Agreeableness, Conscientiousness, etc.)
            predictors = ['agreeableness', 'conscientiousness', 'extraversion', 'openness']
            found_predictors = [p for p in predictors if p in content]
            if len(found_predictors) >= 1:
                score += 10
                feedback_parts.append(f"Report lists predictors ({len(found_predictors)}/4 found).")
            
            # Check for Lambda/Penalty
            if 'lambda' in content or 'penalty' in content:
                score += 10
                feedback_parts.append("Report mentions regularization penalty (lambda).")
                
        except Exception as e:
            feedback_parts.append(f"Failed to parse report: {str(e)}")
        finally:
            if os.path.exists(temp_report.name):
                os.unlink(temp_report.name)
    else:
        feedback_parts.append("Report text file not found.")

    # ------------------------------------------------------------------
    # Final Scoring
    # ------------------------------------------------------------------
    passed = score >= 70
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }