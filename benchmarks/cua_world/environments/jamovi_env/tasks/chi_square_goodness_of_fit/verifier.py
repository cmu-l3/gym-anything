#!/usr/bin/env python3
"""
Verifier for chi_square_goodness_of_fit task in Jamovi.

Verification Strategy:
1. File Existence: Check if TitanicGoF.omv was created during the task.
2. Content Parsing: Unzip .omv (which is a ZIP archive) and inspect JSON metadata.
   - Verify correct analysis type (propTestN / N Outcomes)
   - Verify correct variable (passengerClass)
   - Verify 'expected counts' option was enabled
3. VLM Verification: Use trajectory frames to verify UI interaction steps 
   (loading data, selecting menu, viewing results).
"""

import json
import os
import zipfile
import tempfile
import logging
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_chi_square_goodness_of_fit(traj, env_info, task_info):
    """
    Verify the Chi-Square Goodness of Fit task.
    """
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
        return {"passed": False, "score": 0, "feedback": f"Failed to load task result: {e}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    # =========================================================
    # CRITERION 1: File Existence & Validity (15 points)
    # =========================================================
    output_exists = task_result.get('output_exists', False)
    created_during = task_result.get('file_created_during_task', False)
    output_path = task_result.get('output_path', '')

    if output_exists and created_during:
        score += 15
        feedback_parts.append("Output file created successfully.")
    elif output_exists:
        score += 5
        feedback_parts.append("Output file exists but wasn't created during this task session.")
    else:
        feedback_parts.append("Output file TitanicGoF.omv not found.")

    # =========================================================
    # CRITERION 2: File Content Analysis (50 points)
    # =========================================================
    analysis_correct = False
    variable_correct = False
    options_correct = False
    
    if output_exists:
        # Retrieve the OMV file
        temp_omv = tempfile.NamedTemporaryFile(delete=False, suffix='.omv')
        try:
            copy_from_env(output_path, temp_omv.name)
            
            # OMV is a ZIP file. We look for index.json or analysis definitions
            if zipfile.is_zipfile(temp_omv.name):
                with zipfile.ZipFile(temp_omv.name, 'r') as zf:
                    # Jamovi stores analysis metadata in 'index.json' or inside 'analysis' folder
                    # We'll search for 'index.json' first which usually lists analyses
                    if 'index.json' in zf.namelist():
                        with zf.open('index.json') as f:
                            index_data = json.load(f)
                            
                        # Look for the analysis
                        # Structure typically: { "analyses": [ { "type": "jmv::propTestN", ... } ] }
                        analyses = index_data.get('analyses', [])
                        
                        for analysis in analyses:
                            # Check for N Outcomes (Goodness of Fit)
                            # Identifier is usually 'jmv::propTestN' or similar
                            a_type = analysis.get('name', '') or analysis.get('type', '')
                            
                            if 'propTestN' in a_type or 'NOutcomes' in a_type:
                                analysis_correct = True
                                
                                # Check parameters/options
                                options = analysis.get('options', {})
                                
                                # Variable check
                                var = options.get('var', '')
                                if var == 'passengerClass':
                                    variable_correct = True
                                
                                # Options check: Expected counts
                                # Usually stored as "expected": true in options
                                if options.get('expected', False) is True:
                                    options_correct = True
                                    
                                break
                    else:
                        feedback_parts.append("Valid OMV zip but couldn't find index.json.")
            else:
                feedback_parts.append("Output file is not a valid OMV/ZIP archive.")
                
        except Exception as e:
            feedback_parts.append(f"Error parsing OMV file: {str(e)}")
        finally:
            if os.path.exists(temp_omv.name):
                os.unlink(temp_omv.name)

    # Score based on parsing
    if analysis_correct:
        score += 20
        feedback_parts.append("Correct analysis type detected (Goodness of Fit).")
    else:
        feedback_parts.append("Could not verify analysis type in file.")

    if variable_correct:
        score += 15
        feedback_parts.append("Correct variable (passengerClass) used.")
    elif analysis_correct:
        feedback_parts.append("Wrong variable selected.")

    if options_correct:
        score += 15
        feedback_parts.append("Expected counts option enabled.")
    elif analysis_correct:
        feedback_parts.append("Expected counts option NOT enabled.")

    # =========================================================
    # CRITERION 3: VLM Workflow Verification (35 points)
    # =========================================================
    # We use VLM to verify the visual workflow, which covers gaps if file parsing fails
    # and ensures the agent actually interacted with the UI.
    
    frames = sample_trajectory_frames(traj, n=5)
    final_frame = get_final_screenshot(traj)
    
    vlm_prompt = """
    You are verifying if a user successfully performed a Chi-Square Goodness of Fit test in Jamovi.
    
    Review the sequence of screenshots. A successful workflow includes:
    1. Opening a dataset (TitanicSurvival - look for data grid with 'passengerClass', 'survived', etc.)
    2. Navigating to the 'Frequencies' menu.
    3. Selecting 'N Outcomes' or 'Goodness of Fit'.
    4. A results table appearing with "Chi-Square Goodness of Fit".
    5. The results table showing 'passengerClass' as the variable.
    6. 'Expected Counts' appearing in the results table columns.
    
    Answer the following in JSON:
    {
        "data_loaded": boolean,
        "menu_accessed": boolean,
        "results_visible": boolean,
        "expected_counts_visible": boolean,
        "confidence": "high/medium/low"
    }
    """
    
    vlm_score = 0
    try:
        if frames:
            # Include final frame in analysis
            all_frames = frames + ([final_frame] if final_frame else [])
            vlm_result = query_vlm(images=all_frames, prompt=vlm_prompt)
            
            if vlm_result and vlm_result.get('success'):
                parsed = vlm_result.get('parsed', {})
                
                if parsed.get('data_loaded'):
                    vlm_score += 10
                    feedback_parts.append("VLM: Data loading observed.")
                
                if parsed.get('menu_accessed') and parsed.get('results_visible'):
                    vlm_score += 15
                    feedback_parts.append("VLM: Analysis workflow observed.")
                
                if parsed.get('expected_counts_visible'):
                    vlm_score += 10
                    feedback_parts.append("VLM: Expected counts visible in output.")
            else:
                feedback_parts.append("VLM verification failed to process images.")
    except Exception as e:
        logger.error(f"VLM error: {e}")
        # Fallback scoring if file check was perfect
        if analysis_correct and variable_correct and options_correct:
            vlm_score = 35
            feedback_parts.append("VLM skipped (file perfect).")

    score += vlm_score

    # Final check
    passed = score >= 60 and analysis_correct
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback_parts)
    }