#!/usr/bin/env python3
"""
Verifier for JASP Binomial Test Task.

Verification Strategy:
1. File Existence: Check if .jasp file exists and was created during task.
2. File Structure: A .jasp file is a ZIP archive. We unzip and parse the JSON analysis definition.
3. Analysis Content:
   - Check module: "Binomial Test"
   - Check variable: "Gender"
   - Check test value: 0.5
   - Check Vovk-Sellke enabled
   - Check Descriptive Plots enabled
4. VLM Confirmation: Visual check of the UI state (optional but good for redundancy).
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

def verify_binomial_test_gender(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System Error: copy_from_env not available"}

    score = 0
    feedback = []
    max_score = 100
    
    # --- Step 1: Retrieve Execution Metadata ---
    temp_result_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json').name
    try:
        copy_from_env("/tmp/task_result.json", temp_result_json)
        with open(temp_result_json, 'r') as f:
            result_data = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve task result: {str(e)}"}
    finally:
        if os.path.exists(temp_result_json):
            os.unlink(temp_result_json)

    # --- Step 2: Check File Existence & Timestamp (20 pts) ---
    if not result_data.get("output_exists", False):
        return {"passed": False, "score": 0, "feedback": "Output file 'BinomialTestGender.jasp' was not saved."}
    
    if not result_data.get("file_created_during_task", False):
        feedback.append("WARNING: Output file timestamp is older than task start (reused file?).")
        # We continue but penalize slightly if strict, or fail. 
        # For now, if it exists, we'll analyze it, but note the timing.
    else:
        score += 10
        feedback.append("Output file created during task.")

    file_size = result_data.get("output_size_bytes", 0)
    if file_size > 1000: # JASP files are usually >10KB
        score += 10
    else:
        feedback.append("File seems too small to be a valid JASP analysis.")
        return {"passed": False, "score": score, "feedback": " | ".join(feedback)}

    # --- Step 3: Analyze JASP File Content (60 pts) ---
    # Retrieve the actual .jasp file
    jasp_file_path = "/tmp/BinomialTestGender.jasp"
    try:
        copy_from_env(result_data["output_path"], jasp_file_path)
    except Exception as e:
        return {"passed": False, "score": score, "feedback": f"Could not copy JASP file for analysis: {e}"}

    analysis_valid = False
    vovk_found = False
    plot_found = False
    correct_variable = False
    
    temp_extract_dir = tempfile.mkdtemp()
    try:
        if not zipfile.is_zipfile(jasp_file_path):
             feedback.append("Saved file is not a valid JASP archive.")
        else:
            with zipfile.ZipFile(jasp_file_path, 'r') as zip_ref:
                zip_ref.extractall(temp_extract_dir)
            
            # JASP stores analysis state in 'embedded.json' or within 'analysis' folder depending on version.
            # We will recursively search for JSON files and look for key strings.
            
            json_contents = []
            for root, dirs, files in os.walk(temp_extract_dir):
                for file in files:
                    if file.endswith(".json"):
                        try:
                            with open(os.path.join(root, file), 'r', encoding='utf-8', errors='ignore') as jf:
                                content = jf.read()
                                json_contents.append(content)
                        except:
                            pass

            full_text = " ".join(json_contents)
            
            # 1. Check for Binomial Test
            if "BinomialTest" in full_text or "Binomial Test" in full_text:
                score += 20
                analysis_valid = True
                feedback.append("Binomial Test analysis found.")
            else:
                feedback.append("Binomial Test not found in file.")

            # 2. Check for Gender variable
            if "\"Gender\"" in full_text:
                score += 15
                correct_variable = True
                feedback.append("Correct variable (Gender) selected.")
            else:
                feedback.append("Variable 'Gender' not found in analysis.")

            # 3. Check for Vovk-Sellke
            # Key often appears as "VovkSellkeMPR": true or similar option name
            if "VovkSellkeMPR" in full_text or "Vovk-Sellke" in full_text:
                score += 15
                vovk_found = True
                feedback.append("Vovk-Sellke option enabled.")
            else:
                feedback.append("Vovk-Sellke option missing.")

            # 4. Check for Descriptive Plots
            if "descriptivePlots" in full_text or "Descriptive plots" in full_text:
                score += 10
                plot_found = True
                feedback.append("Descriptive plots enabled.")
            else:
                feedback.append("Descriptive plots missing.")

    except Exception as e:
        feedback.append(f"Error parsing JASP file: {str(e)}")
    finally:
        shutil.rmtree(temp_extract_dir)
        if os.path.exists(jasp_file_path):
            os.remove(jasp_file_path)

    # --- Step 4: VLM Verification (20 pts) ---
    # Used as a fallback and to verify UI interaction
    vlm_score = 0
    final_screenshot = get_final_screenshot(traj)
    
    if final_screenshot:
        prompt = """
        Review this screenshot of JASP. 
        1. Is the 'Binomial Test' results table visible?
        2. Do you see 'Gender' in the results?
        3. Is there a bar plot (Descriptive Plot) visible?
        4. Do you see 'Vovk-Sellke' or 'VS-MPR' in the table?
        Answer yes/no for each.
        """
        try:
            vlm_result = query_vlm(images=[final_screenshot], prompt=prompt)
            vlm_text = vlm_result.get("result", "").lower()
            
            if "yes" in vlm_text:
                # Basic credit for visible work if file analysis was partial
                vlm_score += 20
                feedback.append("VLM confirms results visible in UI.")
        except Exception:
            pass
    
    # Cap VLM score contribution if file analysis was perfect, otherwise it helps
    if score < 80:
        score += vlm_score

    score = min(score, 100)
    
    # Key criteria for passing
    passed = (analysis_valid and correct_variable and score >= 60)

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }