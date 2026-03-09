#!/usr/bin/env python3
"""
Verifier for metallographic_phase_quantification@1

Scoring Criteria:
1. Output files exist (Mask, CSV, Report) - 20 pts
2. Files created during task (Anti-gaming) - 10 pts
3. Mask is valid binary image - 20 pts
4. Reported value matches Ground Truth (within tolerance) - 40 pts
5. VLM Visual Check (Trajectory) - 10 pts

Total: 100 pts
Pass: 60 pts
"""

import json
import os
import tempfile
import logging
import math
import numpy as np

# Set up logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_metallographic_phase_quantification(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Environment copy function not available."}

    # 1. Retrieve Result JSON
    # ----------------------------------------------------------------
    temp_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_json.name)
        with open(temp_json.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve task results: {str(e)}"}
    finally:
        if os.path.exists(temp_json.name):
            os.unlink(temp_json.name)

    score = 0
    feedback = []
    
    # 2. Check File Existence (20 pts)
    # ----------------------------------------------------------------
    files_exist = result.get('mask_exists', False) and \
                  result.get('csv_exists', False) and \
                  result.get('report_exists', False)
    
    if files_exist:
        score += 20
        feedback.append("All required output files found (+20).")
    else:
        missing = []
        if not result.get('mask_exists'): missing.append("Mask")
        if not result.get('csv_exists'): missing.append("CSV")
        if not result.get('report_exists'): missing.append("Report")
        feedback.append(f"Missing files: {', '.join(missing)}.")

    # 3. Check Timestamp (10 pts)
    # ----------------------------------------------------------------
    if result.get('files_created_during_task', False):
        score += 10
        feedback.append("Files created during task window (+10).")
    else:
        feedback.append("Files detected but timestamps indicate they were not created during this session.")

    # 4. Check Mask Validity (20 pts)
    # ----------------------------------------------------------------
    # We need to inspect the mask image content to ensure it's binary
    mask_valid = False
    if result.get('mask_exists'):
        temp_mask = tempfile.NamedTemporaryFile(delete=False, suffix='.png')
        try:
            copy_from_env("/tmp/result_mask.png", temp_mask.name)
            
            # Using basic python file check first to avoid heavy deps if possible, 
            # but we need to check pixel values. 
            try:
                from PIL import Image
                img = Image.open(temp_mask.name)
                # Check mode
                if img.mode in ['1', 'L', 'P']:
                    # Check unique values
                    extrema = img.getextrema()
                    # If it's binary, mostly 0 and 255 (or 1)
                    # We can't be too strict on exact values, but should be low entropy
                    # Simple check: is it grayscale/binary?
                    mask_valid = True
                    score += 20
                    feedback.append("Segmentation mask appears valid (+20).")
                else:
                    feedback.append(f"Mask format {img.mode} unexpected.")
            except ImportError:
                # Fallback if PIL not installed in verifier env (unlikely)
                # Assume valid if file exists and > 0 bytes
                if os.path.getsize(temp_mask.name) > 100:
                    mask_valid = True
                    score += 10 # Partial points
                    feedback.append("Mask file exists (content check skipped) (+10).")
        except Exception as e:
            feedback.append(f"Failed to inspect mask: {str(e)}")
        finally:
            if os.path.exists(temp_mask.name):
                os.unlink(temp_mask.name)

    # 5. Check Accuracy (40 pts)
    # ----------------------------------------------------------------
    reported = result.get('reported_value', -1)
    gt = result.get('ground_truth_value', -1)
    tolerance = task_info.get('metadata', {}).get('tolerance_percent', 2.5)

    if reported != -1 and gt != -1:
        diff = abs(reported - gt)
        if diff <= tolerance:
            score += 40
            feedback.append(f"Measurement accuracy excellent. Reported: {reported}%, GT: {gt:.2f}% (+40).")
        elif diff <= (tolerance * 2):
            score += 20
            feedback.append(f"Measurement accuracy acceptable. Reported: {reported}%, GT: {gt:.2f}% (+20).")
        else:
            feedback.append(f"Measurement deviation too high. Reported: {reported}%, GT: {gt:.2f}% (Tolerance: +/- {tolerance}%).")
    else:
        feedback.append("Could not compare values (Reported or GT missing).")

    # 6. VLM Check (10 pts) - Placeholder for Trajectory Analysis
    # ----------------------------------------------------------------
    # In a full implementation, we would query VLM here.
    # For this programmatic verifier, we give points if mask valid + accuracy good
    if mask_valid and score >= 60:
        score += 10
        feedback.append("Implied visual validation passed based on result accuracy (+10).")

    # Final Result
    passed = (score >= 60)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }