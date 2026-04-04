#!/usr/bin/env python3
"""
Verifier for Multi-Channel ROI Profiling task.

Task requirements:
1. Open 'Fluorescent Cells'
2. Convert to RGB Stack
3. Select 3 nuclei on Slice 3
4. Multi-measure across all 3 slices
5. Save CSV

Verification Points:
- File creation & timestamp (20 pts)
- Data for >= 3 ROIs (25 pts)
- Data for >= 3 Slices/Channels (25 pts)
- Evidence of actual multi-channel data (variance) (15 pts)
- Correct target (Nuclei/Blue channel signal) (15 pts)
"""

import json
import tempfile
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_multichannel_roi_profiling(traj, env_info, task_info):
    """
    Verify the multi-channel ROI profiling task.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System error: copy function unavailable"}

    # 1. Retrieve the pre-parsed JSON summary from the container
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/multichannel_roi_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {
            "passed": False, 
            "score": 0, 
            "feedback": f"Could not retrieve results: {str(e)}"
        }
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback = []
    
    # --- Criterion 1: File Existence & Validity (20 pts) ---
    if result.get("file_exists") and result.get("file_created_during_task"):
        score += 20
        feedback.append("Result file created successfully.")
    elif result.get("file_exists"):
        feedback.append("Result file exists but timestamp indicates it wasn't created during this task.")
    else:
        feedback.append("Result file not found at expected location.")
        return {"passed": False, "score": 0, "feedback": " ".join(feedback)}

    # --- Criterion 2: ROI Count (25 pts) ---
    rois = result.get("unique_rois", 0)
    if rois >= 3:
        score += 25
        feedback.append(f"Measured {rois} distinct ROIs (Target: >=3).")
    else:
        feedback.append(f"Only measured {rois} ROIs. Needed at least 3.")

    # --- Criterion 3: Stack/Slice Measurement (25 pts) ---
    slices = result.get("slices_measured", 0)
    if slices >= 3:
        score += 25
        feedback.append("Data found for all 3 channels/slices.")
    elif slices > 0:
        feedback.append(f"Only data for {slices} slices found. Did you convert to Stack and measure ALL slices?")
    else:
        feedback.append("No slice/channel data found. Ensure you used 'Multi Measure'.")

    # --- Criterion 4: Signal Variance (15 pts) ---
    # Ensures they didn't just measure the same slice 3 times
    if result.get("channel_variance_detected"):
        score += 15
        feedback.append("Intensity variance detected across channels.")
    else:
        feedback.append("Warning: Measurements identical across slices. Did you measure the stack correctly?")

    # --- Criterion 5: Nuclear Signature (15 pts) ---
    # Ensures they likely selected nuclei (Slice 3 is Blue/DAPI)
    if result.get("nuclei_signature_detected"):
        score += 15
        feedback.append("Signal intensity consistent with nuclear selection.")
    else:
        feedback.append("Warning: Low signal intensity. Ensure you selected bright nuclei on the Blue channel.")

    # Pass logic
    passed = score >= 60 and rois >= 3 and slices >= 3

    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }