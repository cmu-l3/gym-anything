#!/usr/bin/env python3
"""
Verifier for Bayesian Independent Samples T-Test Task (JASP).

Verification Strategy:
1. File Existence: Checks for .jasp project and .txt results file.
2. JASP Analysis Parsing:
   - Unzips the .jasp file (it's a zip container).
   - Finds the analysis JSON specification.
   - Verifies the analysis type (Bayesian T-Test).
   - Verifies variable assignment (Mischief=DV, Cloak=Group).
   - Verifies specific plots are enabled.
3. Results Validation:
   - parses the .txt file for BF10 value.
   - checks if BF10 is within a plausible range for the dataset.
   - checks if interpretation matches the BF10 value.
"""

import json
import os
import zipfile
import tempfile
import re
import logging
import shutil

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_bayesian_ttest(traj, env_info, task_info):
    """
    Verify JASP Bayesian T-Test task.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    scoring = metadata.get('scoring', {})
    
    jasp_path = metadata.get('output_jasp_path', '/home/ga/Documents/JASP/InvisibilityCloak_BayesianTTest.jasp')
    txt_path = metadata.get('output_txt_path', '/home/ga/Documents/JASP/bayesian_ttest_results.txt')

    score = 0
    feedback = []
    
    # Setup temporary directory for verification
    work_dir = tempfile.mkdtemp()
    
    try:
        # =========================================================
        # 1. Retrieve and Parse JSON Result Metadata
        # =========================================================
        task_result_path = os.path.join(work_dir, "task_result.json")
        try:
            copy_from_env("/tmp/task_result.json", task_result_path)
            with open(task_result_path, 'r') as f:
                task_res = json.load(f)
        except Exception:
            task_res = {}
            feedback.append("Could not retrieve task metadata JSON.")

        # =========================================================
        # 2. Verify .jasp File (Analysis Structure)
        # =========================================================
        jasp_local_path = os.path.join(work_dir, "project.jasp")
        jasp_valid = False
        analysis_correct = False
        variables_correct = False
        plots_correct = False

        try:
            copy_from_env(jasp_path, jasp_local_path)
            
            if not zipfile.is_zipfile(jasp_local_path):
                feedback.append("JASP file exists but is not a valid JASP/ZIP file.")
            else:
                score += scoring.get('jasp_file_exists', 10)
                jasp_valid = True
                feedback.append("Valid JASP project file found.")

                with zipfile.ZipFile(jasp_local_path, 'r') as z:
                    # JASP files usually store analysis settings in 'analyses/X/analysis-options.json'
                    # We need to find the correct analysis
                    analysis_found = False
                    
                    # Search for analysis definition files
                    for filename in z.namelist():
                        if filename.endswith("analysis-options.json") or filename.endswith("state.json"):
                            try:
                                with z.open(filename) as json_file:
                                    data = json.load(json_file)
                                    # Normalize structure (JASP internal format varies by version)
                                    # We look for specific keys identifying the analysis
                                    
                                    # Check for Analysis Name/Type
                                    # Format often: { "name": "TTestBayesianIndependentSamples", ... }
                                    # Or nested in a list
                                    
                                    json_str = json.dumps(data)
                                    
                                    if "TTestBayesianIndependentSamples" in json_str:
                                        analysis_found = True
                                        analysis_correct = True
                                        
                                        # Check Variables
                                        # Look for "dependent": "Mischief" or "variables": ["Mischief"]
                                        if '"Mischief"' in json_str and '"Cloak"' in json_str:
                                            variables_correct = True
                                        
                                        # Check Plots
                                        # "priorAndPosteriorPlot": true
                                        # "bfRobustnessPlot": true
                                        if '"priorAndPosteriorPlot": true' in json_str or '"priorAndPosteriorPlot":true' in json_str:
                                            if '"bfRobustnessPlot": true' in json_str or '"bfRobustnessPlot":true' in json_str:
                                                plots_correct = True
                                        
                                        break # Found the target analysis
                            except Exception as e:
                                logger.warning(f"Error parsing internal JASP json {filename}: {e}")

                    if analysis_correct:
                        score += scoring.get('correct_analysis_type', 15)
                        feedback.append("Correct Bayesian T-Test analysis found.")
                    else:
                        feedback.append("Could not find 'Bayesian Independent Samples T-Test' in project.")
                    
                    if variables_correct:
                        score += scoring.get('correct_variables', 15)
                        feedback.append("Variables correctly assigned (Mischief/Cloak).")
                    else:
                        feedback.append("Variable assignment incorrect or not found.")

                    if plots_correct:
                        score += scoring.get('plots_enabled', 20)
                        feedback.append("Required plots (Prior/Posterior, Robustness) enabled.")
                    else:
                        feedback.append("Required diagnostic plots not enabled.")

        except Exception as e:
            feedback.append(f"Failed to retrieve/parse JASP file: {e}")

        # =========================================================
        # 3. Verify Text Results (BF10 value)
        # =========================================================
        txt_local_path = os.path.join(work_dir, "results.txt")
        bf10_val = None
        
        try:
            copy_from_env(txt_path, txt_local_path)
            score += scoring.get('results_file_exists', 15)
            
            with open(txt_local_path, 'r') as f:
                content = f.read()
            
            # Extract BF10 using regex
            # Matches: "BF10: 1.23", "BF10 : 0.5", etc.
            match = re.search(r'BF10\s*[:=]\s*([0-9]*\.?[0-9]+)', content, re.IGNORECASE)
            if match:
                bf10_val = float(match.group(1))
                
                # Verify Range
                min_val = metadata.get('bf10_min', 0.3)
                max_val = metadata.get('bf10_max', 5.0)
                
                if min_val <= bf10_val <= max_val:
                    score += scoring.get('bf10_value_correct', 10)
                    feedback.append(f"BF10 value ({bf10_val}) is within expected range.")
                    
                    # Verify Interpretation consistency
                    # Logic: 
                    # 1-3: Anecdotal
                    # 3-10: Moderate
                    # >10: Strong
                    interpretation_score = 0
                    lower_content = content.lower()
                    
                    if 1.0 <= bf10_val < 3.0:
                        if "anecdotal" in lower_content: interpretation_score = 1
                    elif 3.0 <= bf10_val < 10.0:
                        if "moderate" in lower_content: interpretation_score = 1
                    elif bf10_val < 1.0:
                        if "no evidence" in lower_content or "h0" in lower_content: interpretation_score = 1
                    
                    # Fallback: just check if they wrote *something* reasonable looking
                    if "evidence" in lower_content:
                        interpretation_score = 1
                        
                    if interpretation_score > 0:
                        score += scoring.get('interpretation_consistent', 10)
                        feedback.append("Interpretation appears consistent.")
                else:
                    feedback.append(f"BF10 value ({bf10_val}) is outside expected range [{min_val}, {max_val}].")
            else:
                feedback.append("Could not find 'BF10: <value>' in text file.")
                
        except Exception:
            feedback.append("Results text file not found or unreadable.")

    finally:
        shutil.rmtree(work_dir)

    # =========================================================
    # 4. Final Scoring
    # =========================================================
    
    # Cap score at 100
    score = min(score, 100)
    
    # Pass Condition: Score >= 60 AND critical checks passed
    # Critical: JASP file must be valid and Analysis type correct
    critical_pass = jasp_valid and analysis_correct
    
    passed = (score >= 60) and critical_pass
    
    if not critical_pass:
        feedback.insert(0, "CRITICAL FAIL: Valid JASP file with correct analysis type not found.")
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }