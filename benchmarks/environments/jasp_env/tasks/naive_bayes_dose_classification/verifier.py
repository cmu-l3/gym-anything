#!/usr/bin/env python3
"""
Verifier for Naive Bayes Dose Classification task in JASP.

Verification Logic:
1. File Existence: Checks for .jasp and .txt report files.
2. Anti-Gaming: Checks timestamps to ensure files were created during the task.
3. Content Analysis: Parses the text report for key terms (Naive Bayes, variables) and plausible metrics.
4. VLM Verification: Uses trajectory frames to confirm UI interaction (variable type change, ML module usage).
"""

import json
import os
import re
import tempfile
import logging
from gym_anything.vlm import sample_trajectory_frames, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_naive_bayes_dose_classification(traj, env_info, task_info):
    """
    Verify the Naive Bayes classification task.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Initialize scoring
    score = 0
    max_score = 100
    feedback_parts = []
    
    # Load metadata expectations
    metadata = task_info.get('metadata', {})
    expected_jasp_path = metadata.get('expected_jasp_file', '/home/ga/Documents/JASP/NaiveBayesDose.jasp')
    expected_report_path = metadata.get('expected_report_file', '/home/ga/Documents/JASP/naive_bayes_report.txt')
    
    # ------------------------------------------------------------------
    # 1. Retrieve Task Result JSON
    # ------------------------------------------------------------------
    temp_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_json.name)
        with open(temp_json.name, 'r') as f:
            task_result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve task result: {str(e)}"}
    finally:
        if os.path.exists(temp_json.name):
            os.unlink(temp_json.name)

    # ------------------------------------------------------------------
    # 2. Verify JASP File (Persistence) - 15 Points
    # ------------------------------------------------------------------
    jasp_exists = task_result.get('jasp_file_exists', False)
    jasp_fresh = task_result.get('jasp_created_during_task', False)
    jasp_size = task_result.get('jasp_file_size', 0)

    if jasp_exists and jasp_fresh and jasp_size > 10000: # JASP files with data/analysis are usually >10KB
        score += 15
        feedback_parts.append("JASP analysis file saved correctly.")
    elif jasp_exists:
        score += 5
        feedback_parts.append("JASP file exists but might be stale or empty.")
    else:
        feedback_parts.append("JASP analysis file not found.")

    # ------------------------------------------------------------------
    # 3. Verify Report File Content - 45 Points
    # ------------------------------------------------------------------
    report_exists = task_result.get('report_file_exists', False)
    report_fresh = task_result.get('report_created_during_task', False)
    
    if report_exists and report_fresh:
        # Retrieve the actual report content
        temp_report = tempfile.NamedTemporaryFile(delete=False, suffix='.txt')
        try:
            copy_from_env(expected_report_path, temp_report.name)
            with open(temp_report.name, 'r', encoding='utf-8', errors='ignore') as f:
                content = f.read().lower()
            
            # Check 3.1: Algorithm Name (10 pts)
            if "naive bayes" in content:
                score += 10
                feedback_parts.append("Report correctly identifies Naive Bayes.")
            else:
                feedback_parts.append("Report missing algorithm name 'Naive Bayes'.")

            # Check 3.2: Variables (10 pts)
            if "dose" in content and ("len" in content or "supp" in content):
                score += 10
                feedback_parts.append("Report mentions target/predictor variables.")
            else:
                feedback_parts.append("Report missing key variable names.")

            # Check 3.3: Accuracy (15 pts)
            # Look for a floating point number between 0.40 and 0.99
            accuracies = re.findall(r"0\.\d+", content)
            valid_acc = [float(a) for a in accuracies if 0.40 <= float(a) <= 0.99]
            if valid_acc:
                score += 15
                feedback_parts.append(f"Report includes valid accuracy metric ({valid_acc[0]}).")
            else:
                feedback_parts.append("Report missing or invalid accuracy value.")

            # Check 3.4: Confusion Matrix content (10 pts)
            # Simple heuristic: looking for 3x3 layout related text or explicit mention
            if "confusion" in content or "matrix" in content:
                # Check for some integers that look like counts
                digits = re.findall(r"\b\d{1,2}\b", content)
                if len(digits) >= 4: # At least a few cells of the matrix
                    score += 10
                    feedback_parts.append("Report appears to contain confusion matrix data.")
                else:
                    score += 5
                    feedback_parts.append("Report mentions confusion matrix but data is sparse.")
        except Exception as e:
            feedback_parts.append(f"Failed to analyze report content: {e}")
        finally:
            if os.path.exists(temp_report.name):
                os.unlink(temp_report.name)
    else:
        feedback_parts.append("Report file not created or timestamp invalid.")

    # ------------------------------------------------------------------
    # 4. VLM Trajectory Verification - 40 Points
    # ------------------------------------------------------------------
    # We verify the PROCESS: Did they actually use JASP?
    
    frames = sample_trajectory_frames(traj, n=6)
    
    vlm_prompt = """
    You are verifying a user performing a Naive Bayes classification task in JASP.
    Look at the sequence of screenshots.
    
    Check for the following specific evidences:
    1. Is the "Machine Learning" module or "Naive Bayes Classification" panel visible?
    2. Is there a "Confusion Matrix" table visible in the results pane (usually on the right)?
    3. Is the "dose" variable icon changed to a Venn diagram (Nominal) or Bar chart (Ordinal), rather than a Ruler (Scale)?
    
    Output JSON:
    {
        "ml_module_visible": true/false,
        "naive_bayes_header_visible": true/false,
        "confusion_matrix_visible": true/false,
        "variable_type_nominal": true/false
    }
    """
    
    try:
        vlm_result = query_vlm(images=frames, prompt=vlm_prompt)
        parsed = vlm_result.get('parsed', {})
        
        # Scoring VLM
        if parsed.get('ml_module_visible') or parsed.get('naive_bayes_header_visible'):
            score += 15
            feedback_parts.append("VLM confirmed Machine Learning/Naive Bayes module usage.")
        
        if parsed.get('confusion_matrix_visible'):
            score += 15
            feedback_parts.append("VLM confirmed Confusion Matrix generation.")
            
        if parsed.get('variable_type_nominal'):
            score += 10
            feedback_parts.append("VLM confirmed variable type change (Nominal).")
        else:
            feedback_parts.append("VLM could not clearly confirm variable type change.")
            
    except Exception as e:
        logger.error(f"VLM verification failed: {e}")
        # Fallback: if report was perfect, give partial trust points
        if score >= 50: 
            score += 10
            feedback_parts.append("VLM failed, adding fallback points based on strong file evidence.")

    # ------------------------------------------------------------------
    # Final Result
    # ------------------------------------------------------------------
    passed = score >= 60 and jasp_exists and report_exists
    
    return {
        "passed": passed,
        "score": min(score, 100),
        "feedback": " ".join(feedback_parts)
    }