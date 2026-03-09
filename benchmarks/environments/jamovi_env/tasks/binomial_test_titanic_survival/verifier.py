#!/usr/bin/env python3
"""
Verifier for Binomial Proportion Test on Titanic Survival.

Verification Strategy:
1. File Existence & Timestamp: Checks if .omv file was created during the task.
2. OMV Analysis (Programmatic): Unzips the .omv (Zip) file to inspect:
   - Metadata JSONs for "Binomial Test" analysis.
   - Configuration (test value = 0.5, variable = survived).
3. VLM Verification: Uses trajectory frames to confirm the user interacted with 
   the Frequencies > Binomial Test menu and configured the analysis correctly.
"""

import json
import os
import tempfile
import zipfile
import shutil
import re
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm

def verify_binomial_test_titanic_survival(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    score = 0
    feedback_parts = []
    
    # ============================================================
    # 1. Retrieve Task Result JSON
    # ============================================================
    temp_result_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_result_file.name)
        with open(temp_result_file.name, 'r') as f:
            task_result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve task result: {e}"}
    finally:
        if os.path.exists(temp_result_file.name):
            os.unlink(temp_result_file.name)

    # ============================================================
    # 2. Check File Existence & Timestamp (Anti-Gaming)
    # ============================================================
    output_exists = task_result.get("output_exists", False)
    created_during = task_result.get("file_created_during_task", False)
    
    if not output_exists:
        return {"passed": False, "score": 0, "feedback": "Output file 'TitanicBinomialTest.omv' not found."}
    
    score += 10
    feedback_parts.append("Output file exists.")

    if not created_during:
        feedback_parts.append("WARNING: File timestamp is older than task start (reused file?).")
    else:
        score += 10
        feedback_parts.append("File created during task.")

    # ============================================================
    # 3. Analyze OMV File Content (Programmatic)
    # ============================================================
    # Jamovi .omv files are ZIP archives containing JSON metadata and data.
    omv_passed = False
    temp_omv = tempfile.NamedTemporaryFile(delete=False, suffix='.omv')
    temp_extract_dir = tempfile.mkdtemp()
    
    try:
        # Copy .omv from env
        copy_from_env(task_result["output_file_path"], temp_omv.name)
        
        # Unzip
        if zipfile.is_zipfile(temp_omv.name):
            with zipfile.ZipFile(temp_omv.name, 'r') as zip_ref:
                zip_ref.extractall(temp_extract_dir)
            
            # Search for analysis definition
            # Usually in a file like 'index.json' or within 'analyses' folder
            analysis_found = False
            test_value_correct = False
            variable_correct = False
            
            # Grep through all JSON files in the extracted archive
            for root, dirs, files in os.walk(temp_extract_dir):
                for file in files:
                    if file.endswith(".json"):
                        try:
                            with open(os.path.join(root, file), 'r', encoding='utf-8', errors='ignore') as jf:
                                content = jf.read()
                                
                                # Check for Binomial Test Analysis identifier
                                # Jamovi internal name is often 'propTest2' or 'binom'
                                if 'propTest2' in content or 'Binomial' in content:
                                    analysis_found = True
                                
                                # Check for configuration
                                # Looking for "testValue": 0.5 or similar patterns
                                if '"testValue": 0.5' in content or '"testValue":0.5' in content:
                                    test_value_correct = True
                                
                                # Check for variable
                                if '"survived"' in content:
                                    variable_correct = True
                        except:
                            pass
            
            if analysis_found:
                score += 20
                feedback_parts.append("Binomial test analysis found in file.")
            else:
                feedback_parts.append("Binomial test analysis NOT found in OMV metadata.")

            if test_value_correct:
                score += 15
                feedback_parts.append("Correct test value (0.5) found.")
            else:
                feedback_parts.append("Could not confirm test value is 0.5.")
                
            if variable_correct:
                score += 15
                feedback_parts.append("Variable 'survived' is used.")
            
            omv_passed = analysis_found and test_value_correct
            
    except Exception as e:
        feedback_parts.append(f"Error analyzing OMV file: {e}")
    finally:
        if os.path.exists(temp_omv.name):
            os.unlink(temp_omv.name)
        shutil.rmtree(temp_extract_dir, ignore_errors=True)

    # ============================================================
    # 4. VLM Verification (Trajectory & Final)
    # ============================================================
    # Use trajectory to confirm they actually used the menu, not just loaded a file
    frames = sample_trajectory_frames(traj, n=4)
    final_img = get_final_screenshot(traj)
    
    vlm_prompt = """
    You are verifying a Jamovi statistics task.
    Goal: Perform a Binomial Test on the 'survived' variable of the Titanic dataset (test value 0.5).
    
    Analyze the screenshots:
    1. Do you see the Jamovi interface?
    2. Is the Titanic dataset loaded (look for cols: survived, sex, age, passengerClass)?
    3. Do you see the 'Frequencies' > '2 Outcomes - Binomial Test' analysis being selected or displayed?
    4. In the result panel (usually on the right), is there a Binomial Test table?
    5. Does the result show a p-value < 0.001 (significant)?
    6. Is there a bar plot showing the counts of 'no' and 'yes' for survival?
    
    Return JSON:
    {
        "jamovi_visible": true,
        "data_loaded": true,
        "binomial_test_visible": true,
        "p_value_significant": true,
        "bar_plot_visible": true
    }
    """
    
    # We query the VLM with the final frame primarily for the result, 
    # and maybe one intermediate frame for the menu if needed. 
    # Here we just use the final + one intermediate to save context window.
    images_to_check = frames[-2:] + [final_img] if len(frames) >= 2 else [final_img]
    
    vlm_result = query_vlm(prompt=vlm_prompt, images=images_to_check)
    
    vlm_score = 0
    if vlm_result and vlm_result.get("success"):
        parsed = vlm_result.get("parsed", {})
        if parsed.get("jamovi_visible"): vlm_score += 5
        if parsed.get("data_loaded"): vlm_score += 5
        if parsed.get("binomial_test_visible"): vlm_score += 10
        if parsed.get("p_value_significant"): vlm_score += 5
        if parsed.get("bar_plot_visible"): vlm_score += 5
        
        feedback_parts.append(f"VLM verification score: {vlm_score}/30")
    else:
        feedback_parts.append("VLM verification failed to run.")
    
    score += vlm_score

    # ============================================================
    # 5. Final Scoring
    # ============================================================
    passed = score >= 60 and omv_passed and output_exists
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }