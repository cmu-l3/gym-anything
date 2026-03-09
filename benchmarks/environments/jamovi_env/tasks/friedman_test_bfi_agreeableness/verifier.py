#!/usr/bin/env python3
"""
Verifier for Friedman Non-Parametric Test task in Jamovi.

Verification Strategy:
1. File Verification:
   - Check if .omv file exists and was created during the task.
   - Unzip the .omv file (which is a ZIP archive) and inspect the JSON analysis definition.
   - Verify specific analysis type (anovaRMNP/Friedman), variables (A1-A5), and options (pairwise, descriptives).

2. VLM Verification:
   - Use trajectory frames to verify the workflow: Data loading -> Analysis configuration -> Results.
   - Check if results table and pairwise comparisons are visible in the final state.
"""

import json
import os
import tempfile
import zipfile
import logging
import shutil
from typing import Dict, Any

# Import VLM utils from framework
try:
    from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm
except ImportError:
    # Fallback for local testing
    def sample_trajectory_frames(traj, n=5): return []
    def get_final_screenshot(traj): return None
    def query_vlm(**kwargs): return {"success": False, "error": "VLM not available"}

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_friedman_test(traj, env_info, task_info):
    """
    Verify the Friedman test task.
    """
    # 1. Setup and retrieve result JSON
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    score = 0
    feedback_parts = []
    
    # Load task result metadata
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            task_result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve task result: {e}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    # 2. Verify .omv file existence and timestamps (Anti-gaming)
    if not task_result.get("output_exists", False):
        return {"passed": False, "score": 0, "feedback": "Output .omv file not found."}
    
    if not task_result.get("file_created_during_task", False):
        return {"passed": False, "score": 0, "feedback": "Output file was not created/modified during the task session."}

    score += 10
    feedback_parts.append("File created successfully (10/10)")

    # 3. Analyze .omv content
    # Jamovi .omv files are ZIP archives containing JSON definitions of the analysis
    omv_path = task_result.get("output_path")
    temp_omv = tempfile.NamedTemporaryFile(delete=False, suffix='.zip')
    extract_dir = tempfile.mkdtemp()
    
    analysis_found = False
    correct_vars = False
    pairwise_enabled = False
    descriptives_enabled = False
    
    try:
        copy_from_env(omv_path, temp_omv.name)
        
        if os.path.getsize(temp_omv.name) < 1000:
             return {"passed": False, "score": score, "feedback": "Output file is too small to contain valid analysis."}
        
        with zipfile.ZipFile(temp_omv.name, 'r') as zip_ref:
            zip_ref.extractall(extract_dir)
            
        # Search for analysis JSONs (usually in index.json or distinct analysis files)
        # We look for files containing "anovaRMNP" (Repeated Measures Non-Parametric) or "friedman"
        
        json_files = []
        for root, dirs, files in os.walk(extract_dir):
            for file in files:
                if file.endswith(".json"):
                    json_files.append(os.path.join(root, file))
        
        for json_file in json_files:
            try:
                with open(json_file, 'r') as f:
                    data = json.load(f)
                    
                    # Convert to string for easy searching or traverse dict
                    data_str = json.dumps(data)
                    
                    # Check for Analysis Type: Friedman (anovaRMNP)
                    # Jamovi internal name is typically 'anovaRMNP' for Friedman
                    if 'anovaRMNP' in data_str or ('friedman' in data_str.lower() and 'test' in data_str.lower()):
                        analysis_found = True
                        
                        # Check Variables
                        # Should contain A1, A2, A3, A4, A5 in the variables list
                        vars_present = 0
                        for var in ["A1", "A2", "A3", "A4", "A5"]:
                            if f'"{var}"' in data_str:
                                vars_present += 1
                        
                        if vars_present == 5:
                            correct_vars = True
                        
                        # Check Options
                        # Pairwise: "pairs": true or "postHoc"
                        if '"pairs": true' in data_str or '"pairs":true' in data_str or 'durbin' in data_str.lower():
                            pairwise_enabled = True
                            
                        # Descriptives: "desc": true
                        if '"desc": true' in data_str or '"desc":true' in data_str or '"descriptives": true' in data_str:
                            descriptives_enabled = True
                            
                        # If we found the specific analysis, we can stop searching, 
                        # but keep checking in case there are multiple analyses
                        if correct_vars and pairwise_enabled and descriptives_enabled:
                            break
            except:
                continue

    except Exception as e:
        logger.error(f"Error analyzing .omv file: {e}")
        feedback_parts.append(f"Error analyzing file content: {e}")
    finally:
        if os.path.exists(temp_omv.name):
            os.unlink(temp_omv.name)
        shutil.rmtree(extract_dir, ignore_errors=True)

    # Score File Content
    if analysis_found:
        score += 30
        feedback_parts.append("Friedman analysis found (30/30)")
    else:
        feedback_parts.append("Friedman analysis NOT found in file")
        
    if correct_vars:
        score += 20
        feedback_parts.append("Correct variables (A1-A5) used (20/20)")
    elif analysis_found:
        feedback_parts.append("Incorrect variables used")

    if pairwise_enabled:
        score += 10
        feedback_parts.append("Pairwise comparisons enabled (10/10)")
    
    if descriptives_enabled:
        score += 10
        feedback_parts.append("Descriptives enabled (10/10)")

    # 4. VLM Verification
    # We use VLM to verify the visual state, serving as a backup and ensuring data was actually loaded
    frames = sample_trajectory_frames(traj, n=4)
    final_img = get_final_screenshot(traj)
    
    vlm_score = 0
    if final_img:
        prompt = """
        Analyze this screenshot of Jamovi statistical software.
        1. Is a dataset visible in the spreadsheet view (look for rows of numbers)?
        2. Is there a results panel visible on the right?
        3. Does the results panel show a "Friedman" test table?
        4. Are there "Pairwise Comparisons" or "Descriptives" tables visible?
        
        Respond in JSON:
        {
            "data_visible": true/false,
            "results_visible": true/false,
            "friedman_table_visible": true/false,
            "details_visible": true/false
        }
        """
        
        vlm_res = query_vlm(prompt=prompt, image=final_img)
        if vlm_res.get("success"):
            parsed = vlm_res.get("parsed", {})
            if parsed.get("data_visible") or parsed.get("results_visible"):
                vlm_score += 10
            if parsed.get("friedman_table_visible"):
                vlm_score += 10
            
            feedback_parts.append(f"Visual verification score: {vlm_score}/20")
        else:
            # Fallback if VLM fails but file was perfect
            if analysis_found and correct_vars:
                vlm_score = 20
                feedback_parts.append("VLM unavailable, trusting file analysis")

    score += vlm_score

    passed = score >= 60 and analysis_found
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }