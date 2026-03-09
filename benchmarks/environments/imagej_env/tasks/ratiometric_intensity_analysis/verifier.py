#!/usr/bin/env python3
import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_ratiometric_analysis(traj, env_info, task_info):
    """
    Verifies the Ratiometric Intensity Analysis task.
    
    Criteria:
    1. Output file exists and created during task (10 pts)
    2. Output is 32-bit floating point (25 pts)
    3. Image Math: Correlation with Ground Truth > 0.9 (30 pts)
    4. Masking: Background pixels are properly zeroed/NaN (20 pts)
    5. Reported mean value matches calculated mean (15 pts)
    """
    
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System error: copy functionality missing"}

    # Load result JSON from container
    temp_json = tempfile.NamedTemporaryFile(delete=False, suffix=".json")
    try:
        copy_from_env("/tmp/task_result.json", temp_json.name)
        with open(temp_json.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load verification results: {str(e)}"}
    finally:
        if os.path.exists(temp_json.name):
            os.unlink(temp_json.name)

    score = 0
    feedback = []
    
    # 1. File Existence (10 pts)
    if result.get('file_exists') and result.get('file_created_during_task'):
        score += 10
        feedback.append("Output file created successfully.")
    else:
        feedback.append("Output file missing or not created during task.")
        return {"passed": False, "score": 0, "feedback": " ".join(feedback)}

    # 2. Bit Depth (25 pts)
    if result.get('is_float32'):
        score += 25
        feedback.append("Correct 32-bit floating-point format.")
    else:
        feedback.append("Incorrect image format. Expected 32-bit float (likely used 8-bit or 16-bit).")

    # 3. Image Math Correlation (30 pts)
    correlation = result.get('correlation', 0.0)
    if correlation > 0.95:
        score += 30
        feedback.append(f"High correlation with ground truth ({correlation:.4f}). Calculation looks correct.")
    elif correlation > 0.8:
        score += 15
        feedback.append(f"Moderate correlation ({correlation:.4f}). Check ratio logic.")
    else:
        feedback.append(f"Low correlation ({correlation:.4f}). The image content does not match expected Ratio = Red/Green.")

    # 4. Masking Accuracy (20 pts)
    masking_score = result.get('masking_score', 0.0)
    if masking_score > 0.95:
        score += 20
        feedback.append("Background successfully masked.")
    elif masking_score > 0.5:
        score += 10
        feedback.append("Background partially masked.")
    else:
        feedback.append("Background masking failed. Background pixels should be 0 or NaN.")

    # 5. Reported Mean (15 pts)
    reported = result.get('reported_mean', 0.0)
    calculated = result.get('calculated_mean', 0.0)
    
    # Allow 5% tolerance
    if calculated != 0:
        diff = abs(reported - calculated)
        pct_diff = (diff / abs(calculated)) * 100
        if pct_diff < 5.0:
            score += 15
            feedback.append(f"Reported mean ({reported}) matches actual image mean ({calculated:.4f}).")
        else:
            feedback.append(f"Reported mean ({reported}) deviates from image mean ({calculated:.4f}).")
    elif result.get('txt_exists'):
         feedback.append("Could not verify mean value accuracy (reference calculation failed or image invalid).")

    # Final Pass check
    passed = score >= 60 and result.get('is_float32') # Essential technical requirement
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }