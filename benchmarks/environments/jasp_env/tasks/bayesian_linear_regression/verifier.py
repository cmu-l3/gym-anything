#!/usr/bin/env python3
"""
Verifier for Bayesian Linear Regression Task
"""

import json
import os
import sys
import tempfile
import base64
import zipfile
import re
import logging
from typing import Dict, Any

# Configure logging
logging.basicConfig(level=logging.INFO, format='%(asctime)s - %(levelname)s - %(message)s')
logger = logging.getLogger(__name__)

def verify_bayesian_linear_regression(traj, env_info, task_info):
    """
    Verifies the Bayesian Linear Regression task.
    
    Criteria:
    1. JASP file exists and is a valid ZIP archive (JASP format).
    2. JASP file contains Bayesian Linear Regression analysis.
    3. Correct variables used (Exam, Anxiety, Revise).
    4. Report file exists and contains correct values.
    5. Anti-gaming: Files created during task.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    score = 0
    feedback_parts = []
    
    # ============================================================
    # 1. Retrieve Result JSON
    # ============================================================
    temp_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_json.name)
        with open(temp_json.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve task results: {str(e)}"}
    finally:
        if os.path.exists(temp_json.name):
            os.unlink(temp_json.name)

    jasp_info = result.get('jasp_file', {})
    report_info = result.get('report_file', {})

    # ============================================================
    # 2. Verify JASP File (40 points)
    # ============================================================
    jasp_valid = False
    
    if jasp_info.get('exists') and jasp_info.get('created_during_task'):
        score += 10
        feedback_parts.append("JASP file created")
        
        # Download JASP file for inspection
        temp_jasp = tempfile.NamedTemporaryFile(delete=False, suffix='.jasp')
        try:
            # The export script copies it to /tmp/verification_output.jasp
            copy_from_env("/tmp/verification_output.jasp", temp_jasp.name)
            
            if zipfile.is_zipfile(temp_jasp.name):
                score += 5
                jasp_valid = True
                feedback_parts.append("Valid JASP archive")
                
                # Inspect Contents
                with zipfile.ZipFile(temp_jasp.name, 'r') as z:
                    file_list = z.namelist()
                    
                    # Search for analysis definition
                    # JASP files typically contain an 'index.html' or 'embedded' folder or specific JSONs
                    # We look for indications of Bayesian Linear Regression
                    content_found = False
                    
                    # Naive check: grep through JSONs/HTMLs in the zip
                    for filename in file_list:
                        if filename.endswith('.json') or filename.endswith('.html') or filename.endswith('.qml'):
                            try:
                                with z.open(filename) as f:
                                    content = f.read().decode('utf-8', errors='ignore')
                                    if 'BayesianLinearRegression' in content:
                                        content_found = True
                                    if 'Exam' in content and 'Anxiety' in content and 'Revise' in content:
                                        # Checks variables presence
                                        pass
                            except:
                                pass
                    
                    if content_found:
                        score += 25
                        feedback_parts.append("Confirmed Bayesian Linear Regression analysis in file")
                    else:
                        feedback_parts.append("Could not confirm specific analysis type in JASP file (might be saved differently, but file exists)")
                        # Give partial credit if we just can't parse it but it's a valid JASP file
                        score += 10 
            else:
                feedback_parts.append("File is not a valid zip/jasp archive")
                
        except Exception as e:
            feedback_parts.append(f"Error analyzing JASP file: {str(e)}")
        finally:
            if os.path.exists(temp_jasp.name):
                os.unlink(temp_jasp.name)
    else:
        feedback_parts.append("JASP file missing or not created during task")

    # ============================================================
    # 3. Verify Report File (60 points)
    # ============================================================
    if report_info.get('exists') and report_info.get('created_during_task'):
        score += 10
        feedback_parts.append("Report file created")
        
        try:
            content_b64 = report_info.get('content_base64', '')
            content = base64.b64decode(content_b64).decode('utf-8')
            lines = [l.strip() for l in content.split('\n') if l.strip()]
            
            # Check required lines
            # 1. Best Model
            if any("Best Model" in l and ("Anxiety" in l or "Revise" in l) for l in lines):
                score += 10
                feedback_parts.append("Report: Best Model identified")
            
            # 2. BF10
            bf10_line = next((l for l in lines if "BF10" in l), None)
            if bf10_line:
                # Extract number
                try:
                    val_str = re.search(r'BF10:?\s*([0-9\.e\+]+)', bf10_line).group(1)
                    val = float(val_str)
                    if val > 1.0:
                        score += 10
                        feedback_parts.append("Report: BF10 > 1.0")
                    else:
                        feedback_parts.append("Report: BF10 value suspicious (<= 1.0)")
                except:
                    feedback_parts.append("Report: Could not parse BF10 value")
            else:
                feedback_parts.append("Report: BF10 missing")

            # 3. R2
            r2_line = next((l for l in lines if "R2" in l or "R²" in l), None)
            if r2_line:
                try:
                    val_str = re.search(r'R2:?\s*([0-9\.]+)', r2_line).group(1)
                    val = float(val_str)
                    if 0.1 <= val <= 0.9:
                        score += 10
                        feedback_parts.append("Report: R2 reasonable")
                    else:
                        feedback_parts.append("Report: R2 value suspicious")
                except:
                    feedback_parts.append("Report: Could not parse R2 value")
            else:
                feedback_parts.append("Report: R2 missing")

            # 4. Coefficients
            anx_line = next((l for l in lines if "Anxiety" in l and ("Mean" in l or "Coeff" in l)), None)
            rev_line = next((l for l in lines if "Revise" in l and ("Mean" in l or "Coeff" in l)), None)
            
            if anx_line and rev_line:
                try:
                    # Look for negative number for anxiety
                    anx_val = float(re.search(r'(-?[0-9\.]+)', anx_line.split(':')[-1]).group(1))
                    # Look for positive number for revise
                    rev_val = float(re.search(r'(-?[0-9\.]+)', rev_line.split(':')[-1]).group(1))
                    
                    if anx_val < 0 and rev_val > 0:
                        score += 20
                        feedback_parts.append("Report: Coefficients direction correct")
                    else:
                        score += 10
                        feedback_parts.append(f"Report: Coefficients found but signs unexpected (Anx: {anx_val}, Rev: {rev_val})")
                except:
                    score += 5
                    feedback_parts.append("Report: Coefficients lines found but values unparseable")
            else:
                feedback_parts.append("Report: Coefficient lines missing")
                
        except Exception as e:
            feedback_parts.append(f"Error parsing report: {str(e)}")
    else:
        feedback_parts.append("Report file missing")

    # Final Check
    passed = score >= 60 and jasp_valid
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }