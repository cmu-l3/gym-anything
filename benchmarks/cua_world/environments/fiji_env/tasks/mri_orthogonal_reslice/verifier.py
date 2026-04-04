#!/usr/bin/env python3
import json
import os
import tempfile
import re

def verify_mri_reslice(traj, env_info, task_info):
    """
    Verifies the MRI Orthogonal Reslice task.
    
    Scoring Criteria (100 pts total):
    1. Coronal Stack created & valid (>1MB, new) [15 pts]
    2. Sagittal Stack created & valid (>1MB, new) [15 pts]
    3. Axial Profile CSV created & has data (>100 rows) [15 pts]
    4. Coronal Profile CSV created & has data (>50 rows) [10 pts]
    5. Orthogonal Montage PNG created & valid size [15 pts]
    6. Report content checks (Brain width, Calibration, Dimensions) [20 pts]
    7. Anti-gaming (Timestamps check) [10 pts]
    
    Pass Threshold: 60 pts
    """
    
    # 1. Retrieve result data from environment
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System error: copy_from_env not available"}
    
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve task results: {str(e)}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)
            
    score = 0
    feedback = []
    
    files = result.get('files', {})
    csv_analysis = result.get('csv_analysis', {})
    report_text = result.get('report_content', "")
    
    # --- Criterion 1: Coronal Stack (15 pts) ---
    c_stack = files.get('coronal_stack', {})
    if c_stack.get('exists') and c_stack.get('created_during_task'):
        # Check size (should be large for a stack, e.g., > 1MB)
        if c_stack.get('size', 0) > 1000000:
            score += 15
            feedback.append("Coronal stack created successfully.")
        else:
            score += 5
            feedback.append("Coronal stack file exists but seems too small (not a full stack?).")
    else:
        feedback.append("Coronal stack not found or not created during task.")

    # --- Criterion 2: Sagittal Stack (15 pts) ---
    s_stack = files.get('sagittal_stack', {})
    if s_stack.get('exists') and s_stack.get('created_during_task'):
        if s_stack.get('size', 0) > 1000000:
            score += 15
            feedback.append("Sagittal stack created successfully.")
        else:
            score += 5
            feedback.append("Sagittal stack file exists but seems too small.")
    else:
        feedback.append("Sagittal stack not found.")

    # --- Criterion 3: Axial Profile (15 pts) ---
    ax_prof = files.get('axial_profile', {})
    if ax_prof.get('exists') and ax_prof.get('created_during_task'):
        rows = csv_analysis.get('axial_profile_rows', 0)
        # Brain width is ~130-150mm, so at 1mm res, at least 100 points expected
        if rows > 100:
            score += 15
            feedback.append("Axial profile extracted successfully.")
        elif rows > 0:
            score += 10
            feedback.append("Axial profile exists but has few data points.")
        else:
            feedback.append("Axial profile exists but is empty.")
    else:
        feedback.append("Axial profile not found.")

    # --- Criterion 4: Coronal Profile (10 pts) ---
    cor_prof = files.get('coronal_profile', {})
    if cor_prof.get('exists') and cor_prof.get('created_during_task'):
        rows = csv_analysis.get('coronal_profile_rows', 0)
        if rows > 50:
            score += 10
            feedback.append("Coronal profile extracted successfully.")
        else:
            score += 5
            feedback.append("Coronal profile exists but has few data points.")
    else:
        feedback.append("Coronal profile not found.")

    # --- Criterion 5: Montage (15 pts) ---
    montage = files.get('montage', {})
    if montage.get('exists') and montage.get('created_during_task'):
        # Arbitrary size check for a decent image
        if montage.get('size', 0) > 10000: 
            score += 15
            feedback.append("Montage created successfully.")
        else:
            score += 5
            feedback.append("Montage exists but file size is suspiciously small.")
    else:
        feedback.append("Montage not found.")

    # --- Criterion 6: Report Content (20 pts) ---
    report_score = 0
    report_feedback = []
    
    if files.get('report', {}).get('exists'):
        # Check for calibration mention
        if "1.5" in report_text and "mm" in report_text.lower():
            report_score += 5
            report_feedback.append("Calibration info found")
            
        # Check for brain width (looking for number between 100 and 200)
        # Regex for a number likely to be the width
        width_match = re.search(r'(width|brain).*?(\d{3})', report_text.lower())
        width_match_float = re.search(r'(width|brain).*?(\d{3}\.\d+)', report_text.lower())
        
        # Simpler check: find any number between 120 and 180
        numbers = re.findall(r"[-+]?\d*\.\d+|\d+", report_text)
        valid_width_found = False
        for num in numbers:
            try:
                val = float(num)
                if 120 <= val <= 180:
                    valid_width_found = True
                    break
            except:
                pass
        
        if valid_width_found:
            report_score += 10
            report_feedback.append("Valid brain width measurement found")
        else:
            report_feedback.append("No valid brain width (120-180mm) identified in report")

        # Check for dimensions keywords
        if "slice" in report_text.lower() or "x" in report_text.lower():
            report_score += 5
            report_feedback.append("Dimensions info found")
            
        score += report_score
        feedback.append(f"Report analysis: {', '.join(report_feedback)}.")
    else:
        feedback.append("Report file not found.")

    # --- Criterion 7: Anti-gaming (10 pts) ---
    # If we have at least 3 output files created *during* the task
    created_count = 0
    for fkey in ['coronal_stack', 'sagittal_stack', 'axial_profile', 'coronal_profile', 'montage', 'report']:
        if files.get(fkey, {}).get('created_during_task'):
            created_count += 1
            
    if created_count >= 3:
        score += 10
        feedback.append("Anti-gaming timestamp check passed.")
    else:
        feedback.append("Anti-gaming check failed (too few new files created).")

    return {
        "passed": score >= 60,
        "score": score,
        "feedback": " ".join(feedback)
    }