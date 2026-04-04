#!/usr/bin/env python3
"""
Verifier for ordinal_regression_bigfive task.

Checks:
1. JASP project file exists and contains valid Ordinal Logistic Regression analysis.
2. Text report exists and contains reasonable values for McFadden R2 and Parallel Lines test.
"""

import json
import os
import tempfile
import zipfile
import re
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_ordinal_regression_bigfive(traj, env_info, task_info):
    """
    Verifies the JASP Ordinal Logistic Regression task.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    score = 0
    max_score = 100
    feedback_parts = []
    
    # Files to retrieve
    result_json_path = "/tmp/task_result.json"
    jasp_remote_path = "/home/ga/Documents/JASP/Ordinal_A1_Analysis.jasp"
    
    # Temp files for analysis
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    temp_jasp = tempfile.NamedTemporaryFile(delete=False, suffix='.jasp')
    
    try:
        # 1. Load result JSON
        copy_from_env(result_json_path, temp_result.name)
        with open(temp_result.name, 'r') as f:
            result_data = json.load(f)
            
        jasp_info = result_data.get('jasp_file', {})
        report_info = result_data.get('report_file', {})
        
        # --- CRITERION 1: JASP File Existence (10 pts) ---
        if jasp_info.get('exists') and jasp_info.get('created_during_task'):
            score += 10
            feedback_parts.append("JASP file saved.")
        else:
            feedback_parts.append("JASP file missing or not saved during task.")
            return {"passed": False, "score": 0, "feedback": " | ".join(feedback_parts)}

        # --- CRITERION 2: Report Existence (10 pts) ---
        if report_info.get('exists'):
            score += 10
            feedback_parts.append("Report file created.")
        else:
            feedback_parts.append("Report file missing.")
            
        # --- CRITERION 3: JASP Internal Analysis Verification (40 pts) ---
        # Copy the actual JASP file to inspect contents
        try:
            copy_from_env(jasp_remote_path, temp_jasp.name)
            
            if zipfile.is_zipfile(temp_jasp.name):
                with zipfile.ZipFile(temp_jasp.name, 'r') as z:
                    # List files to find where analysis data is stored
                    # JASP files typically have an 'index.html' or 'results' folder
                    file_list = z.namelist()
                    
                    # Search for evidence of Ordinal Regression in analysis specifications
                    # Usually in 'analyses.json' or within the HTML content
                    analysis_found = False
                    vars_correct = False
                    options_correct = False
                    
                    # Method A: Check for JSON definition (if accessible/readable)
                    # We iterate through files looking for json content that mentions "ordinalLogisticRegression"
                    json_content = ""
                    for fname in file_list:
                        if fname.endswith('.json'):
                            try:
                                content = z.read(fname).decode('utf-8', errors='ignore')
                                if 'ordinalLogisticRegression' in content or 'Ordinal Logistic Regression' in content:
                                    analysis_found = True
                                    json_content += content
                            except:
                                pass
                    
                    # Method B: Check HTML results for headers
                    html_content = ""
                    if 'index.html' in file_list:
                         html_content = z.read('index.html').decode('utf-8', errors='ignore')
                    
                    if not analysis_found and 'Ordinal Logistic Regression' in html_content:
                        analysis_found = True

                    if analysis_found:
                        score += 20
                        feedback_parts.append("Ordinal Regression analysis found.")
                        
                        # Check Variables in the JSON blob
                        # Looking for patterns like "dependent": "A1" or similar
                        # Since JSON structure varies, we check for presence of variable names in proximity
                        if '"A1"' in json_content and '"Gender"' in json_content and '"Age"' in json_content:
                            # A bit loose, but verifies they were selected in the UI
                            score += 10
                            vars_correct = True
                            feedback_parts.append("Correct variables selected.")
                        else:
                            feedback_parts.append("Could not confirm specific variables in JASP file.")

                        # Check Options (McFadden, Parallel Lines)
                        # Look for these strings in the raw content
                        if "McFadden" in json_content or "McFadden" in html_content:
                            score += 5
                            options_correct = True
                        if "Test of parallel lines" in json_content or "Test of parallel lines" in html_content:
                            score += 5
                            options_correct = True
                        
                        if options_correct:
                            feedback_parts.append("Required options (McFadden/Parallel Lines) enabled.")
                    else:
                        feedback_parts.append("No Ordinal Logistic Regression found in project file.")
            else:
                feedback_parts.append("Saved file is not a valid JASP archive.")
                
        except Exception as e:
            logger.error(f"Failed to inspect JASP file: {e}")
            feedback_parts.append("Error inspecting JASP file content.")

        # --- CRITERION 4: Report Content Verification (40 pts) ---
        report_text = report_info.get('content', '')
        
        # Check for numeric values
        # We look for a number between 0 and 1 for R2, and a P-value
        # Regex for floating point numbers
        floats = re.findall(r"0\.\d+", report_text)
        
        content_score = 0
        if len(floats) >= 1:
            content_score += 10 # Found at least one number
            
        # Check keywords
        if "McFadden" in report_text or "R2" in report_text or "R^2" in report_text:
            content_score += 10
        if "p-value" in report_text or "parallel" in report_text.lower():
            content_score += 10
        if "hold" in report_text.lower() or "violate" in report_text.lower() or "significant" in report_text.lower():
            content_score += 10 # Interpretation present
            
        if content_score > 0:
            score += content_score
            feedback_parts.append(f"Report content valid (Score: {content_score}).")
        else:
            feedback_parts.append("Report content appears empty or invalid.")

    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Verification error: {str(e)}"}
        
    finally:
        # Cleanup
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)
        if os.path.exists(temp_jasp.name):
            os.unlink(temp_jasp.name)

    passed = score >= 70
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }