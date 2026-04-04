#!/usr/bin/env python3
"""
Verifier for Mann-Whitney U Test task in Jamovi.

Verification Strategy:
1. OMV File Analysis (Primary):
   - Unzips the .omv file (which is a ZIP archive).
   - Scans internal JSON metadata for key analysis options:
     - "mann": true (Mann-Whitney U)
     - "desc": true (Descriptives)
     - "ttestIS" (Independent Samples T-Test analysis type)
     - Filter usage (existence of filter logic or subsetting)
2. Anti-Gaming:
   - Checks file modification time against task start.
3. VLM Verification (Secondary):
   - Checks trajectory frames for visual evidence of the results table.
"""

import json
import os
import zipfile
import tempfile
import logging
import re
from gym_anything.vlm import sample_trajectory_frames, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_mann_whitney_insectsprays(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System error: copy_from_env not available"}

    # 1. Retrieve Result JSON
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result_data = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve task metadata: {str(e)}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    score = 0
    feedback = []
    
    # 2. Check File Existence & Timestamp (20 pts)
    if not result_data.get("output_exists", False):
        return {"passed": False, "score": 0, "feedback": "Output file 'InsectSprays_MannWhitney.omv' not found."}
    
    score += 10
    feedback.append("Output file exists.")

    if result_data.get("file_created_during_task", False):
        score += 10
        feedback.append("File created during task session.")
    else:
        feedback.append("Warning: File timestamp is too old.")

    # 3. Analyze OMV File Content (50 pts)
    # The .omv file is a zip. We copy it out and inspect the JSONs inside.
    omv_temp = tempfile.NamedTemporaryFile(delete=False, suffix='.omv')
    omv_valid = False
    analysis_found = False
    mann_whitney_found = False
    descriptives_found = False
    filter_found = False

    try:
        copy_from_env(result_data["output_path"], omv_temp.name)
        
        if zipfile.is_zipfile(omv_temp.name):
            omv_valid = True
            with zipfile.ZipFile(omv_temp.name, 'r') as z:
                # Iterate through all files in the zip to find JSONs
                # Jamovi analyses are typically in numerical folders like '1/0.json', '2/0.json' or 'meta'
                for filename in z.namelist():
                    if filename.endswith('.json'):
                        try:
                            with z.open(filename) as f:
                                content_str = f.read().decode('utf-8')
                                # We check for substrings because the exact JSON structure varies by version
                                # but the keys are consistent.
                                
                                # Check for Independent Samples T-Test Analysis
                                if '"type": "ttestIS"' in content_str or '"type": "jmv::ttestIS"' in content_str:
                                    analysis_found = True
                                    
                                    # Check for options WITHIN the analysis JSON
                                    if '"mann": true' in content_str:
                                        mann_whitney_found = True
                                    if '"desc": true' in content_str:
                                        descriptives_found = True
                                    
                                # Check for Filter
                                # Filters often appear in 'meta' or analysis options
                                if '"filters":' in content_str or "spray == 'C'" in content_str:
                                    # Loose check for the filter string or structure
                                    filter_found = True
                                    
                        except Exception:
                            continue
    except Exception as e:
        feedback.append(f"Error analyzing OMV file: {str(e)}")
    finally:
        if os.path.exists(omv_temp.name):
            os.unlink(omv_temp.name)

    if omv_valid:
        score += 10 # Valid Jamovi file
        if analysis_found:
            score += 10
            feedback.append("T-Test analysis found.")
        else:
            feedback.append("No Independent Samples T-Test analysis found.")
            
        if mann_whitney_found:
            score += 15
            feedback.append("Mann-Whitney U test enabled.")
        else:
            feedback.append("Mann-Whitney U option NOT enabled.")
            
        if descriptives_found:
            score += 5
            feedback.append("Descriptives enabled.")
            
        if filter_found:
            score += 10
            feedback.append("Data filter detected.")
        else:
            feedback.append("No evidence of data filtering found in metadata.")
    else:
        feedback.append("Output file is not a valid Jamovi archive.")

    # 4. VLM Verification (30 pts)
    # We use trajectory frames to verify the visual workflow
    frames = sample_trajectory_frames(traj, n=4)
    if not frames:
        # Fallback to final screenshot if trajectory missing
        try:
            copy_from_env(result_data.get("screenshot_path"), "final_scr.png")
            frames = ["final_scr.png"]
        except:
            frames = []

    vlm_score = 0
    if frames:
        prompt = """
        You are verifying a Jamovi statistics task. 
        Look at the screenshots. The user should have:
        1. Loaded the 'InsectSprays' dataset.
        2. Filtered the data (look for a filter bar or rows grayed out).
        3. Run an Independent Samples T-Test.
        4. The results table should show 'Mann-Whitney U'.
        
        Answer JSON: {"mann_whitney_visible": bool, "filter_visible": bool, "data_loaded": bool}
        """
        
        try:
            vlm_res = query_vlm(images=frames, prompt=prompt)
            parsed = vlm_res.get("parsed", {})
            
            if parsed.get("data_loaded"):
                vlm_score += 5
            if parsed.get("mann_whitney_visible"):
                vlm_score += 15
                feedback.append("VLM confirmed Mann-Whitney results visible.")
            if parsed.get("filter_visible"):
                vlm_score += 10
                feedback.append("VLM confirmed filter UI visible.")
                
        except Exception as e:
            logger.error(f"VLM error: {e}")
            # If VLM fails but programmatic passed, be lenient
            if mann_whitney_found:
                vlm_score += 15
    
    score += vlm_score

    # Final tally
    passed = score >= 60 and mann_whitney_found and result_data.get("output_exists")
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }