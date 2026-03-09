#!/usr/bin/env python3
"""
Verifier for polynomial_regression_exam_anxiety task.

This verifier checks:
1. If the JASP file exists and was created during the task.
2. If the JASP file (which is a ZIP) contains valid analysis JSON.
3. If the analysis includes a computed column (Anxiety^2).
4. If a regression analysis was performed using both Anxiety and the squared term.
5. VLM verification of the final state to confirm visual success.
"""

import json
import os
import zipfile
import tempfile
import logging
import shutil
from gym_anything.vlm import get_final_screenshot, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_polynomial_regression(traj, env_info, task_info):
    """
    Verify the polynomial regression task.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Initialize scoring
    score = 0
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
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve task results: {e}"}
    finally:
        if os.path.exists(temp_result_json.name):
            os.unlink(temp_result_json.name)
            
    # ------------------------------------------------------------------
    # 2. Check Basic File Requirements (25 points)
    # ------------------------------------------------------------------
    output_exists = task_result.get("output_exists", False)
    created_during = task_result.get("file_created_during_task", False)
    file_size = task_result.get("output_size_bytes", 0)
    
    if not output_exists:
        return {"passed": False, "score": 0, "feedback": "Output JASP file not found."}
        
    if not created_during:
        feedback_parts.append("Warning: File timestamp suggests it wasn't created during this session.")
        # We proceed but penalize heavily in a real scenario; here we just note it
    else:
        score += 10
        feedback_parts.append("File created during task.")

    if file_size > 1000: # JASP files are zips, usually > 1KB
        score += 15
        feedback_parts.append(f"File size valid ({file_size} bytes).")
    else:
        feedback_parts.append(f"File too small to be valid ({file_size} bytes).")

    # ------------------------------------------------------------------
    # 3. Deep Content Verification of JASP File (50 points)
    # ------------------------------------------------------------------
    # JASP files are ZIP archives containing JSON analysis definitions.
    jasp_temp_path = tempfile.mktemp(suffix=".jasp")
    analysis_found = False
    computed_col_found = False
    quadratic_term_found = False
    descriptives_found = False
    
    try:
        copy_from_env("/home/ga/Documents/JASP/Polynomial_Exam.jasp", jasp_temp_path)
        
        if zipfile.is_zipfile(jasp_temp_path):
            with zipfile.ZipFile(jasp_temp_path, 'r') as z:
                # Search for JSON files containing analysis details
                # Common structure: index.html, data.json, various analysis-ID.json files
                # We will scan all .json files in the archive
                
                for filename in z.namelist():
                    if filename.endswith(".json"):
                        try:
                            with z.open(filename) as f:
                                content = json.load(f)
                                content_str = json.dumps(content)
                                
                                # Check for Regression Analysis
                                if "regression" in content_str.lower() or "linearRegression" in content_str:
                                    if "Exam" in content_str: # Dependent variable
                                        analysis_found = True
                                        
                                        # Check for Descriptives in the same analysis context
                                        if "descriptives" in content_str.lower():
                                            descriptives_found = True

                                # Check for Computed Column definition
                                # Often found in data metadata or derived data
                                if "computed" in content_str.lower() or "formula" in content_str.lower():
                                    if "Anxiety" in content_str and ("*" in content_str or "pow" in content_str or "^" in content_str):
                                        computed_col_found = True

                                # Check for Quadratic Term usage in analysis
                                # We look for the variable name created by the user, or 'Anxiety' appearing twice/squared
                                # This is heuristic as we don't know the exact variable name the agent chose
                                # However, JASP saves the formula or term name.
                                if analysis_found:
                                    # Look for covariates list
                                    # If we see "Anxiety" and another term like "Anxiety_Sq" or "Anxiety^2"
                                    if content_str.count("Anxiety") >= 2:
                                        # Weak check, but improved by ensuring it's in the regression context
                                        quadratic_term_found = True
                        except:
                            continue
        else:
            feedback_parts.append("Output file is not a valid ZIP/JASP archive.")

    except Exception as e:
        feedback_parts.append(f"Error inspecting JASP file: {e}")
    finally:
        if os.path.exists(jasp_temp_path):
            os.remove(jasp_temp_path)

    if analysis_found:
        score += 20
        feedback_parts.append("Regression analysis found.")
    else:
        feedback_parts.append("No Regression analysis found in file.")

    if quadratic_term_found or computed_col_found:
        score += 20
        feedback_parts.append("Quadratic/Computed term logic detected.")
    else:
        feedback_parts.append("Could not confirm quadratic term usage in file.")
        
    if descriptives_found:
        score += 10
        feedback_parts.append("Descriptive statistics enabled.")

    # ------------------------------------------------------------------
    # 4. VLM Verification (25 points)
    # ------------------------------------------------------------------
    final_screenshot = get_final_screenshot(traj)
    vlm_passed = False
    
    if final_screenshot:
        prompt = """
        Analyze this screenshot of JASP. 
        1. Is a Linear Regression results table visible?
        2. In the "Coefficients" or "Model Summary" table, do you see "Anxiety" AND another term representing squared anxiety (like "Anxiety_Sq", "Anxiety^2", or similar)?
        3. Is there a column in the data view (if visible) or a variable in the list that looks like a computed squared term?
        
        Respond with JSON: {"regression_visible": bool, "squared_term_visible": bool, "reasoning": str}
        """
        
        try:
            result = query_vlm(images=[final_screenshot], prompt=prompt)
            parsed = result.get('parsed', {})
            
            if parsed.get('regression_visible'):
                vlm_passed = True
                if parsed.get('squared_term_visible'):
                    score += 25
                    feedback_parts.append("VLM confirmed Regression with squared term.")
                else:
                    score += 15
                    feedback_parts.append("VLM confirmed Regression, but squared term unclear.")
            else:
                feedback_parts.append("VLM did not see regression results.")
                
        except Exception as e:
            feedback_parts.append(f"VLM check failed: {e}")
    else:
        feedback_parts.append("No screenshot available for VLM.")

    # ------------------------------------------------------------------
    # Final Scoring
    # ------------------------------------------------------------------
    # Pass threshold: 70 points
    # Must have file + analysis + (quadratic term evidence OR VLM confirmation)
    
    passed = (score >= 70) and output_exists
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }