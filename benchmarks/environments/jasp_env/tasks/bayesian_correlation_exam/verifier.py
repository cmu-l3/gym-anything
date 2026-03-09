#!/usr/bin/env python3
"""
Verifier for Bayesian Correlation Task in JASP.

Verification Strategy:
1. Check if the output .jasp file exists and was created during the task.
2. Validate the .jasp file structure (it's a ZIP file).
3. Extract and parse the analysis JSON inside the .jasp file to verify:
   - Analysis type is Bayesian Correlation.
   - Variables (Exam, Anxiety, Revise) are included.
   - Specific options (Credible Intervals, Plots) are enabled.
4. Fallback/Confirmation via VLM on trajectory/final screenshot.
"""

import json
import os
import zipfile
import tempfile
import shutil
import logging
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_bayesian_correlation(traj, env_info, task_info):
    """
    Verifies the JASP Bayesian Correlation task.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    feedback_parts = []
    score = 0
    passed = False

    # Retrieve metadata
    metadata = task_info.get('metadata', {})
    expected_path = metadata.get('expected_output_path', '/home/ga/Documents/JASP/BayesianCorrelationExam.jasp')
    
    # 1. Get Export Result
    result_data = {}
    temp_result_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json').name
    try:
        copy_from_env("/tmp/task_result.json", temp_result_json)
        with open(temp_result_json, 'r') as f:
            result_data = json.load(f)
    except Exception as e:
        logger.error(f"Failed to load task result JSON: {e}")
        return {"passed": False, "score": 0, "feedback": "Failed to retrieve task execution data"}
    finally:
        if os.path.exists(temp_result_json):
            os.unlink(temp_result_json)

    # 2. Check File Existence and Timestamp (Anti-gaming)
    if not result_data.get("output_exists", False):
        return {"passed": False, "score": 0, "feedback": "Output .jasp file not found."}

    if not result_data.get("file_created_during_task", False):
        feedback_parts.append("File exists but was not modified during the task.")
        # We continue but penalty applies
    else:
        score += 10
        feedback_parts.append("Output file created during task.")

    # 3. Analyze JASP File Content
    # JASP files are ZIPs. We need to copy it out and inspect contents.
    temp_jasp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.jasp').name
    analysis_verified = False
    
    try:
        copy_from_env(expected_path, temp_jasp_file)
        
        if not zipfile.is_zipfile(temp_jasp_file):
            feedback_parts.append("Output file is not a valid JASP/ZIP archive.")
        else:
            score += 10 # Valid zip
            
            with zipfile.ZipFile(temp_jasp_file, 'r') as z:
                # JASP structure varies but usually contains 'index.json' or folders in 'analyses/'
                file_list = z.namelist()
                
                # Search for analysis definition. 
                # Modern JASP format often puts analysis specs in individual JSONs under implicit paths or a main state file.
                # We will look for JSON files and search for keywords.
                
                json_files = [f for f in file_list if f.endswith('.json')]
                analysis_found = False
                vars_found = 0
                opts_found = 0
                
                required_vars = set(["Exam", "Anxiety", "Revise"])
                
                for json_file in json_files:
                    try:
                        with z.open(json_file) as jf:
                            content = json.load(jf)
                            content_str = json.dumps(content)
                            
                            # Check for Bayesian Correlation Analysis Type
                            # Usually identifier is "BayesianCorrelation" or similar in "name" or "title"
                            if "BayesianCorrelation" in content_str or ("Bayesian" in content_str and "Correlation" in content_str):
                                analysis_found = True
                            
                            # Check Variables
                            # Variables are often in "variables" list or encoded in settings
                            # We do a robust string check
                            found_in_this_file = 0
                            for var in required_vars:
                                if var in content_str:
                                    found_in_this_file += 1
                            vars_found = max(vars_found, found_in_this_file)
                            
                            # Check Options
                            if "credibleInterval" in content_str or "\"ci\":true" in content_str.replace(" ", ""):
                                opts_found += 1
                            if "scatterPlot" in content_str or "\"plotScatter\":true" in content_str.replace(" ", ""):
                                opts_found += 1
                                
                    except Exception as e:
                        continue

                if analysis_found:
                    score += 30
                    feedback_parts.append("Bayesian Correlation analysis found in file.")
                else:
                    feedback_parts.append("Could not identify Bayesian Correlation analysis in file.")

                if vars_found >= 3:
                    score += 20
                    feedback_parts.append("All required variables found in analysis.")
                elif vars_found > 0:
                    score += 10
                    feedback_parts.append(f"Only {vars_found}/3 variables found.")
                else:
                    feedback_parts.append("Required variables not found in analysis.")

                # Options check (flexible matching)
                # We give partial credit if specific flags aren't perfectly matched due to version diffs,
                # but we check file size as a proxy for plots too.
                file_size_kb = result_data.get("output_size_bytes", 0) / 1024
                
                # Plots usually bloat the file significantly
                if file_size_kb > 50: 
                    score += 10
                    feedback_parts.append("File size indicates plots are likely present.")
                    opts_found = max(opts_found, 1) # Assume plots exist if big
                
                if opts_found >= 1:
                    score += 10
                    feedback_parts.append("Configuration options (plots/intervals) detected.")
                
                if analysis_found and vars_found >= 3:
                    analysis_verified = True

    except Exception as e:
        feedback_parts.append(f"Error analyzing JASP file: {e}")
    finally:
        if os.path.exists(temp_jasp_file):
            os.unlink(temp_jasp_file)

    # 4. VLM Verification (Visual confirmation)
    # This is critical if the file parsing is ambiguous
    frames = sample_trajectory_frames(traj, n=4)
    final_screen = get_final_screenshot(traj)
    
    vlm_prompt = """
    Review the sequence of screenshots from a JASP statistical analysis task.
    Check for the following evidence:
    1. A "Bayesian Correlation Matrix" table is visible.
    2. The table includes "BF10" (Bayes Factor) values.
    3. The variables "Exam", "Anxiety", and "Revise" are in the table.
    4. There are scatter plots visible (matrix of dots/lines).
    5. The analysis options panel shows "Credible intervals" checked.
    
    Answer JSON with boolean keys: table_visible, bf_values_visible, variables_correct, plots_visible.
    """
    
    vlm_score = 0
    try:
        vlm_result = query_vlm(images=frames + [final_screen], prompt=vlm_prompt)
        parsed = vlm_result.get('parsed', {})
        
        if parsed.get('table_visible'): vlm_score += 5
        if parsed.get('bf_values_visible'): vlm_score += 5
        if parsed.get('variables_correct'): vlm_score += 5
        if parsed.get('plots_visible'): vlm_score += 5
        
        feedback_parts.append(f"VLM Analysis: {json.dumps(parsed)}")
    except Exception as e:
        logger.warning(f"VLM check failed: {e}")
        # If VLM fails, we rely on file analysis, but give benefit of doubt if file was perfect
        if analysis_verified:
            vlm_score = 20

    score += vlm_score

    # Final Pass Determination
    # Must have file created + analysis found + reasonable score
    passed = (result_data.get("file_created_during_task") and 
              analysis_verified and 
              score >= 70)

    return {
        "passed": passed,
        "score": min(score, 100),
        "feedback": " | ".join(feedback_parts)
    }