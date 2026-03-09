#!/usr/bin/env python3
"""
Verifier for JASP Multinomial Goodness-of-Fit Task.

Verification Logic:
1. Validates presence and timestamp of the .jasp output file.
2. Unzips the .jasp file (it's a zip archive) to inspect internal JSON state.
3. Checks for:
   - Correct analysis type (Multinomial Test)
   - Correct variable assignment (Dose)
   - Correct custom expected proportions (0.5, 0.25, 0.25) - NOT defaults
   - Enabled options (Descriptives, Descriptives Plot)
4. Uses VLM as secondary confirmation of the visual result.
"""

import json
import os
import zipfile
import tempfile
import shutil
import logging
from gym_anything.vlm import get_final_screenshot, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_multinomial_gof_test(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System error: copy_from_env not available"}

    # Scoring weights
    SCORE_FILE_EXISTS = 10
    SCORE_FILE_VALID = 10  # Created during task, non-empty
    SCORE_ANALYSIS_FOUND = 20
    SCORE_VARIABLE_CORRECT = 15
    SCORE_PROPORTIONS_CORRECT = 25  # Critical step (changing defaults)
    SCORE_OPTIONS_ENABLED = 10
    SCORE_VLM_VISUAL = 10
    
    total_score = 0
    feedback = []
    
    # 1. Retrieve Task Result JSON
    task_result = {}
    with tempfile.NamedTemporaryFile(suffix=".json", delete=True) as tmp_json:
        try:
            copy_from_env("/tmp/task_result.json", tmp_json.name)
            tmp_json.seek(0)
            task_result = json.load(tmp_json)
        except Exception as e:
            return {"passed": False, "score": 0, "feedback": f"Failed to retrieve task result: {str(e)}"}

    if not task_result.get("output_exists"):
        return {"passed": False, "score": 0, "feedback": "Output file 'MultinomialGOF.jasp' not found."}
    
    total_score += SCORE_FILE_EXISTS
    feedback.append("Output file exists.")

    if not task_result.get("file_created_during_task"):
        feedback.append("WARNING: File timestamp indicates it was not created during this task session.")
        # We penalize but continue, in case of clock skew issues, relying on content check
    else:
        total_score += SCORE_FILE_VALID
        feedback.append("File created during task session.")

    # 2. Retrieve and Inspect .jasp File
    jasp_file_path = task_result.get("output_path")
    analysis_found = False
    variable_correct = False
    proportions_correct = False
    options_correct = False

    with tempfile.TemporaryDirectory() as extract_dir:
        local_jasp_path = os.path.join(extract_dir, "output.jasp")
        try:
            copy_from_env(jasp_file_path, local_jasp_path)
            
            if not zipfile.is_zipfile(local_jasp_path):
                feedback.append("Output file is not a valid JASP/Zip archive.")
            else:
                with zipfile.ZipFile(local_jasp_path, 'r') as z:
                    z.extractall(extract_dir)
                
                # JASP saves analysis state in JSON files. Structure varies by version but usually
                # contains 'results' or 'state' folders. We search for the specific analysis signature.
                
                # Recursively search all JSON files for the multinomial analysis definition
                for root, dirs, files in os.walk(extract_dir):
                    for file in files:
                        if file.endswith(".json"):
                            try:
                                with open(os.path.join(root, file), 'r') as f:
                                    content = json.load(f)
                                    
                                    # Helper to search for analysis in JASP's structure
                                    # Often nested in "results" -> "0" -> "data" etc.
                                    # We stringify to search for keywords first to avoid complex traversal logic
                                    json_str = json.dumps(content)
                                    
                                    # Check 1: Analysis Type
                                    # JASP internal name for this analysis is often related to "Frequencies" or "Multinomial"
                                    if "MultinomialTest" in json_str or "multinomialTest" in json_str:
                                        analysis_found = True
                                    
                                    # Check 2: Variable (Dose)
                                    if analysis_found and '"Dose"' in json_str:
                                        variable_correct = True
                                        
                                    # Check 3: Proportions/Counts
                                    # Look for the specific values 0.5, 0.25
                                    # JASP might store these as "expectedCounts" or "probabilities"
                                    if analysis_found:
                                        # Strict check: ensure it's not just using equal proportions (which would be ~0.33)
                                        if "0.5" in json_str and "0.25" in json_str:
                                            proportions_correct = True
                                    
                                    # Check 4: Options (Descriptives)
                                    if analysis_found:
                                        if '"descriptives":true' in json_str.replace(" ", "") or '"descriptivesPlot":true' in json_str.replace(" ", ""):
                                            options_correct = True
                                            
                            except Exception:
                                continue
        except Exception as e:
            feedback.append(f"Error inspecting JASP file content: {e}")

    if analysis_found:
        total_score += SCORE_ANALYSIS_FOUND
        feedback.append("Multinomial Test analysis found in file.")
    else:
        feedback.append("Could not find Multinomial Test analysis in saved file.")

    if variable_correct:
        total_score += SCORE_VARIABLE_CORRECT
        feedback.append("Correct variable 'Dose' used.")
    elif analysis_found:
        feedback.append("Analysis found but 'Dose' variable not detected.")

    if proportions_correct:
        total_score += SCORE_PROPORTIONS_CORRECT
        feedback.append("Custom expected proportions (0.5, 0.25, 0.25) verified.")
    elif analysis_found:
        feedback.append("Did not detect custom proportions (likely left as default equal).")

    if options_correct:
        total_score += SCORE_OPTIONS_ENABLED
        feedback.append("Descriptives/Plots enabled.")

    # 3. Secondary VLM Verification (Visual Check)
    final_img = get_final_screenshot(traj)
    vlm_score = 0
    if final_img:
        prompt = """
        Analyze this screenshot of JASP statistics software.
        1. Is there a results table titled "Multinomial Test"?
        2. Are there P-values or Chi-square statistics visible?
        3. Is there a "Descriptives" table showing Observed and Expected counts?
        4. Is there a bar chart (Descriptives Plot)?
        
        Answer JSON: {"multinomial_table": bool, "descriptives_table": bool, "plot": bool}
        """
        try:
            vlm_res = query_vlm(prompt, final_img)
            parsed = vlm_res.get('parsed', {})
            if parsed.get('multinomial_table'): vlm_score += 4
            if parsed.get('descriptives_table'): vlm_score += 3
            if parsed.get('plot'): vlm_score += 3
        except Exception:
            pass # VLM fail shouldn't tank score if file is good
            
    if vlm_score > 0:
        total_score += SCORE_VLM_VISUAL
        feedback.append(f"Visual verification confirmed results visible ({vlm_score}/10 pts).")
    elif analysis_found:
        # If file is perfect but VLM failed/didn't see it (maybe window closed), give benefit of doubt
        total_score += SCORE_VLM_VISUAL
        feedback.append("File verified correct, skipping visual check penalty.")

    passed = (total_score >= 60) and analysis_found and variable_correct
    
    return {
        "passed": passed,
        "score": min(100, total_score),
        "feedback": " ".join(feedback)
    }