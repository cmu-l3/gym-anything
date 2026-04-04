#!/usr/bin/env python3
"""
Verifier for PCA BFI-25 Task.

Checks:
1. Jamovi project file (.omv) creation and validity.
2. Text report values (Cumulative Variance, Eigenvalues) against expected ranges.
3. VLM verification of the UI state (Loadings table, Scree plot, Analysis settings).
"""

import json
import os
import re
import tempfile
import logging
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_pca_bfi25_personality(traj, env_info, task_info):
    """
    Verify the PCA task using file artifacts and VLM trajectory analysis.
    """
    # 0. Setup and context
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected = metadata.get('expected_values', {})
    scoring = metadata.get('scoring', {})

    score = 0
    feedback_log = []
    
    # 1. Retrieve Result JSON from container
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve/parse task result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    # 2. File Verification (OMV)
    if result.get('omv_exists') and result.get('omv_modified_during_task'):
        score += scoring.get('omv_exists', 10)
        feedback_log.append("Jamovi project file saved.")
        
        # Check size (empty projects are usually very small, valid ones >10KB typically)
        if result.get('omv_size_bytes', 0) > 10000:
            score += scoring.get('omv_valid', 5)
            feedback_log.append("Project file size indicates content.")
    else:
        feedback_log.append("Jamovi project file missing or not saved during task.")

    # 3. Report Verification (Text Parsing)
    report_content = result.get('report_content', "")
    if result.get('report_exists') and report_content:
        score += scoring.get('report_exists', 10)
        feedback_log.append("Report file created.")

        # Parse values using regex
        # Pattern for Cumulative Variance: "Cumulative Variance...: 44.3"
        cum_var_match = re.search(r"Cumulative.*?Variance.*?:?\s*([\d\.]+)", report_content, re.IGNORECASE)
        # Pattern for Eigenvalue 1: "Component 1 Eigenvalue...: 4.87" OR "Eigenvalue... 1...: 4.87"
        eigen1_match = re.search(r"(?:Component\s*1\s*Eigenvalue|Eigenvalue.*?1).*?:?\s*([\d\.]+)", report_content, re.IGNORECASE)
        # Pattern for Count > 1: "Components.*?Eigenvalue.*?>.*?1.*?:?\s*(\d+)", or just looking for the int at end of line
        count_match = re.search(r"(?:Components.*?Eigenvalue.*?>.*?1).*?:?\s*(\d+)", report_content, re.IGNORECASE)

        # Evaluate Cumulative Variance
        if cum_var_match:
            try:
                val = float(cum_var_match.group(1))
                min_v = expected.get('cumulative_variance_min', 30)
                max_v = expected.get('cumulative_variance_max', 60)
                if min_v <= val <= max_v:
                    score += scoring.get('cum_var_correct', 15)
                    feedback_log.append(f"Cumulative variance ({val}%) within range.")
                else:
                    feedback_log.append(f"Cumulative variance ({val}%) out of range [{min_v}, {max_v}].")
            except ValueError:
                feedback_log.append("Could not parse cumulative variance value.")
        else:
            feedback_log.append("Cumulative variance not found in report.")

        # Evaluate Eigenvalue 1
        if eigen1_match:
            try:
                val = float(eigen1_match.group(1))
                min_v = expected.get('eigenvalue1_min', 3.0)
                max_v = expected.get('eigenvalue1_max', 7.0)
                if min_v <= val <= max_v:
                    score += scoring.get('eigen1_correct', 15)
                    feedback_log.append(f"Component 1 Eigenvalue ({val}) within range.")
                else:
                    feedback_log.append(f"Component 1 Eigenvalue ({val}) out of range [{min_v}, {max_v}].")
            except ValueError:
                feedback_log.append("Could not parse Eigenvalue 1 value.")
        else:
            feedback_log.append("Component 1 Eigenvalue not found in report.")

        # Evaluate Count > 1
        if count_match:
            try:
                val = int(count_match.group(1))
                min_v = expected.get('eigenvalue_gt1_count_min', 4)
                max_v = expected.get('eigenvalue_gt1_count_max', 8)
                if min_v <= val <= max_v:
                    score += scoring.get('eigen_count_correct', 10)
                    feedback_log.append(f"Eigenvalue > 1 count ({val}) within range.")
                else:
                    feedback_log.append(f"Eigenvalue > 1 count ({val}) out of range [{min_v}, {max_v}].")
            except ValueError:
                feedback_log.append("Could not parse eigenvalue count.")
        else:
            feedback_log.append("Eigenvalue count not found in report.")
    else:
        feedback_log.append("Report file missing.")

    # 4. VLM Verification (Visual Checks)
    frames = sample_trajectory_frames(traj, n=5)
    final_screen = get_final_screenshot(traj)
    
    if final_screen:
        frames.append(final_screen)

    # Prompt for VLM
    prompt = """
    You are evaluating a Jamovi statistical analysis session. The user is performing a Principal Component Analysis (PCA).
    
    Examine the provided screenshots of the Jamovi interface. Look for the 'Results' panel (usually on the right).
    
    Please check for the following specific elements:
    1. A 'Component Loadings' table is visible. It should have 5 columns of components (1, 2, 3, 4, 5) and rows for variables (A1, A2, etc.).
    2. A 'Scree Plot' is visible (a line graph showing eigenvalues).
    3. The analysis title in the results panel says 'Principal Component Analysis' (NOT 'Exploratory Factor Analysis').
    4. There is an indication of 'Varimax' rotation in the settings or output notes.
    
    Provide your assessment in JSON format:
    {
        "loadings_table_visible": boolean,
        "scree_plot_visible": boolean,
        "is_pca_analysis": boolean,
        "is_varimax_rotation": boolean,
        "confidence": "high"|"medium"|"low"
    }
    """

    vlm_res = query_vlm(images=frames, prompt=prompt)
    
    if vlm_res and vlm_res.get('success'):
        parsed = vlm_res.get('parsed', {})
        
        if parsed.get('loadings_table_visible'):
            score += scoring.get('vlm_loadings', 15)
            feedback_log.append("VLM: Component loadings table detected.")
            
        if parsed.get('scree_plot_visible'):
            score += scoring.get('vlm_scree', 10)
            feedback_log.append("VLM: Scree plot detected.")
            
        if parsed.get('is_pca_analysis'):
            score += scoring.get('vlm_pca_header', 5)
            feedback_log.append("VLM: Correct PCA analysis type detected.")
            
        if parsed.get('is_varimax_rotation'):
            score += scoring.get('vlm_rotation', 5)
            feedback_log.append("VLM: Varimax rotation detected.")
    else:
        feedback_log.append("VLM verification failed or returned no result.")

    # 5. Final Decision
    passed = score >= 60
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_log)
    }