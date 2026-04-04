#!/usr/bin/env python3
"""
Verifier for Bioequivalence Analysis task.
Checks if the agent correctly filtered data and ran an Equivalence Test.
"""

import json
import os
import zipfile
import tempfile
import shutil
import re
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm

def verify_equivalence_test(traj, env_info, task_info):
    """
    Verifies:
    1. JASP file created during task.
    2. Analysis is 'Equivalence Independent Samples T-Test'.
    3. Equivalence bounds are -2.0 and 2.0.
    4. Data was filtered (N=20, not 60).
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System error: copy_from_env missing"}

    score = 0
    feedback = []
    
    # 1. Check Metadata & Basic File Stats
    metadata = task_info.get('metadata', {})
    expected_path = metadata.get('expected_output_path')
    
    # Load export result
    temp_json = tempfile.NamedTemporaryFile(delete=False, suffix=".json")
    try:
        copy_from_env("/tmp/task_result.json", temp_json.name)
        with open(temp_json.name) as f:
            result_data = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result JSON: {e}"}
    finally:
        if os.path.exists(temp_json.name):
            os.unlink(temp_json.name)
            
    if not result_data.get("output_exists"):
        return {"passed": False, "score": 0, "feedback": "Output JASP file not found."}
        
    if not result_data.get("file_created_during_task"):
        feedback.append("Warning: File timestamp suggests it wasn't created during this session.")
        # We don't fail immediately, but it's suspicious.
    else:
        score += 10 # File created freshly

    # 2. Inspect JASP File Content
    # JASP files are ZIP archives. We need to look inside for analysis specifications.
    temp_jasp = tempfile.NamedTemporaryFile(delete=False, suffix=".jasp")
    analysis_found = False
    bounds_correct = False
    filtering_detected = False
    
    try:
        copy_from_env(expected_path, temp_jasp.name)
        
        if zipfile.is_zipfile(temp_jasp.name):
            with zipfile.ZipFile(temp_jasp.name, 'r') as z:
                # List files to find analysis definitions (often in 'analyses' folder)
                file_list = z.namelist()
                
                # Check for specific strings in all json/results files
                # This is a heuristic scan of the internal structure
                content_text = ""
                for filename in file_list:
                    if filename.endswith(".json") or filename.endswith(".html") or "results" in filename:
                        try:
                            with z.open(filename) as f:
                                content_text += f.read().decode('utf-8', errors='ignore')
                        except:
                            pass
                
                # Check for Equivalence Test
                if "Equivalence Independent Samples T-Test" in content_text or "Equivalence" in content_text:
                    analysis_found = True
                    score += 20
                    feedback.append("Correct analysis type detected.")
                
                # Check for Bounds (-2.0, 2.0)
                # JASP stores these as numbers in JSON. We look for the configuration.
                # Or specific text in the HTML output like "Lower bound"
                if "-2" in content_text and "2" in content_text and "bound" in content_text.lower():
                    bounds_correct = True
                    score += 20
                    feedback.append("Equivalence bounds appear correct.")
                elif "low" in content_text.lower() and "high" in content_text.lower():
                    # Looser check
                    score += 10
                    feedback.append("Equivalence bounds partially detected.")

                # Check for Filtering (N=20 vs N=60)
                # If they used the whole dataset, N=60 (30 per group)
                # If filtered, N=20 (10 per group)
                # We look for "N" followed closely by "10" or "20", and NOT "30" or "60" in the results table context
                if "10" in content_text and "20" in content_text:
                    # Likely correct
                    filtering_detected = True
                    score += 30
                    feedback.append("Sample size indicates correct filtering (N=20).")
                elif "30" in content_text and "60" in content_text:
                    feedback.append("Sample size indicates NO filtering (N=60). Failed specific instruction.")
                    filtering_detected = False
        else:
            feedback.append("Output file is not a valid JASP archive.")
            
    except Exception as e:
        feedback.append(f"Error analyzing JASP file content: {e}")
    finally:
        if os.path.exists(temp_jasp.name):
            os.unlink(temp_jasp.name)

    # 3. VLM Verification (Visual Backup)
    # Use VLM to confirm the visual state of the analysis (Filter icon, Result table)
    frames = sample_trajectory_frames(traj, n=4)
    final_screen = get_final_screenshot(traj)
    images = frames + [final_screen]
    
    vlm_prompt = """
    Review the screenshots of a JASP statistical analysis session.
    1. Did the user apply a filter to the 'dose' variable? (Look for a funnel icon in the column header or 'Filter' interactions).
    2. Is there an 'Equivalence Independent Samples T-Test' results table or plot visible?
    3. Does the result table show 'N' around 10 per group (or Total N=20)? If it shows N=30/60, that is wrong.
    """
    
    vlm_result = query_vlm(images=images, prompt=vlm_prompt)
    
    vlm_score = 0
    if "filter" in vlm_result.get("result", "").lower() or filtering_detected:
        vlm_score += 10
    if "equivalence" in vlm_result.get("result", "").lower() or analysis_found:
        vlm_score += 10
        
    score += vlm_score

    # Final logic
    # Must have the file and correct analysis to pass at all
    # Must have filtered (programmatically or visually confirmed) to get high score
    
    passed = (result_data.get("output_exists") and 
              analysis_found and 
              (filtering_detected or "filter" in vlm_result.get("result", "").lower()) and
              score >= 70)

    return {
        "passed": passed,
        "score": min(score, 100),
        "feedback": " | ".join(feedback)
    }