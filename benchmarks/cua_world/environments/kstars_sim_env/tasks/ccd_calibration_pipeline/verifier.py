#!/usr/bin/env python3
"""
Verifier for ccd_calibration_pipeline task.

Uses multi-signal verification:
1. Programmatic Metadata: Checks that >=5 flats were created after task_start, with correct hardware properties (FRAME_FLAT, V-band).
2. Deterministic Mathematical Array Validation: Re-computes the exact Data Reduction matrix math using the agent's flats and compares the expected Calibrated float arrays to the agent's output files using np.allclose().
3. Trajectory VLM: Ensures the workflow (using IDE/KStars) was functionally performed.
"""

import json
import os
import sys
import tarfile
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

sys.path.insert(0, str(os.path.dirname(__file__)))
try:
    from gym_anything.vlm import sample_trajectory_frames, query_vlm
except ImportError:
    pass

VLM_PROCESS_PROMPT = """You are verifying the workflow of an agent performing astronomical data reduction.
Look at this sequence of chronological trajectory screenshots.

Did the agent progress through the required workflow stages?
1. Open KStars/INDI to capture astronomical images.
2. Open a code editor or terminal and write/execute a Python script using numpy/astropy.

Respond ONLY in valid JSON format:
{
    "kstars_used": true/false,
    "code_written": true/false,
    "confidence": "high/medium/low",
    "reasoning": "Brief description of what is seen."
}
"""

def verify_ccd_calibration(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System error: copy_from_env unavailable"}

    score = 0
    feedback = []
    
    # Create temp workspace
    tmp_dir = tempfile.mkdtemp()
    tmp_json = os.path.join(tmp_dir, "result.json")
    tmp_tar = os.path.join(tmp_dir, "data_export.tar.gz")

    try:
        copy_from_env("/tmp/task_result.json", tmp_json)
        copy_from_env("/tmp/data_export.tar.gz", tmp_tar)
        
        with open(tmp_json, 'r') as f:
            result = json.load(f)
            
        with tarfile.open(tmp_tar, "r:gz") as tar:
            tar.extractall(path=tmp_dir)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve or parse container data: {e}"}

    task_start = result.get('task_start', 0)
    flats = result.get('flats', [])
    calibrated_files = result.get('calibrated_files', [])

    # CRITERION 1: Flats Acquired (20 points)
    # Must be > 0 bytes and created after task start (anti-gaming)
    valid_flats = [f for f in flats if f.get('mtime', 0) > task_start and f.get('size', 0) > 1024]
    
    if len(valid_flats) >= 5:
        score += 20
        feedback.append(f"Acquired {len(valid_flats)} flat frames.")
    elif len(valid_flats) > 0:
        score += 10
        feedback.append(f"Acquired {len(valid_flats)} flat frames (expected 5).")
    else:
        feedback.append("No valid flat frames acquired during task.")

    # CRITERION 2: Correct Hardware Settings (10 points)
    hw_correct = 0
    for f in valid_flats:
        filt = f.get('filter', '').strip().upper()
        itype = f.get('imagetyp', '').strip().upper()
        if 'FLAT' in itype and ('V' in filt or '2' in filt):
            hw_correct += 1
            
    if len(valid_flats) > 0 and hw_correct == len(valid_flats):
        score += 10
        feedback.append("All flats have correct V-band and FRAME_FLAT headers.")
    elif hw_correct > 0:
        score += 5
        feedback.append("Some flats missing V-band or FRAME_FLAT headers.")

    # CRITERION 3: Calibrated Files Generated (10 points)
    if len(calibrated_files) == 3:
        score += 10
        feedback.append("3 calibrated files generated.")
    elif len(calibrated_files) > 0:
        score += 5
        feedback.append(f"{len(calibrated_files)} calibrated files generated.")
    else:
        feedback.append("No calibrated files found in /home/ga/Data/calibrated/.")

    # CRITERION 4: Mathematical Array Precision (40 points)
    math_score = 0
    try:
        import numpy as np
        from astropy.io import fits
        
        data_dir = os.path.join(tmp_dir, "Data")
        
        # Load Darks
        darks = []
        for i in range(1, 4):
            d_path = os.path.join(data_dir, "raw_darks", f"dark_{i}.fits")
            darks.append(fits.getdata(d_path).astype(np.float32))
        master_dark = np.median(darks, axis=0).astype(np.float32)

        # Load Flats (Only the valid ones!)
        flat_arrays = []
        for f in valid_flats:
            f_path = os.path.join(data_dir, "raw_flats", f['name'])
            flat_arrays.append(fits.getdata(f_path).astype(np.float32))
            
        if len(flat_arrays) > 0:
            master_flat = np.median(flat_arrays, axis=0).astype(np.float32)
            mean_flat = np.mean(master_flat)
            if mean_flat == 0:
                mean_flat = 1.0  # Safe fallback to prevent div0
            norm_flat = (master_flat / mean_flat).astype(np.float32)

            # Compare Lights
            correct_calibrations = 0
            for i in range(1, 4):
                agent_path = os.path.join(data_dir, "calibrated", f"calibrated_{i}.fits")
                if os.path.exists(agent_path):
                    raw_light = fits.getdata(os.path.join(data_dir, "raw_lights", f"light_{i}.fits")).astype(np.float32)
                    expected_cal = ((raw_light - master_dark) / norm_flat).astype(np.float32)
                    agent_cal = fits.getdata(agent_path).astype(np.float32)

                    # Tolerances: Absolute tolerance of 1.0 ADU handles minor numpy version casting differences
                    if np.allclose(agent_cal, expected_cal, rtol=1e-3, atol=1.0):
                        correct_calibrations += 1

            # Award ~13 points per exact correct array
            math_score = int((correct_calibrations / 3.0) * 40)
            score += math_score
            feedback.append(f"Mathematical Array Validation: {correct_calibrations}/3 arrays perfect.")
        else:
            feedback.append("Math Validation Failed: Missing flats to compute normalization.")
            
    except ImportError:
        feedback.append("Math Validation Skipped: numpy/astropy missing on host verifier.")
    except Exception as e:
        feedback.append(f"Math Validation Error: {str(e)}")

    # CRITERION 5: VLM Process Verification (20 points)
    vlm_score = 0
    try:
        frames = sample_trajectory_frames(traj, n=5)
        if frames:
            vlm_res = query_vlm(images=frames, prompt=VLM_PROCESS_PROMPT)
            if vlm_res and isinstance(vlm_res, dict):
                if vlm_res.get('kstars_used'):
                    vlm_score += 10
                if vlm_res.get('code_written'):
                    vlm_score += 10
                score += vlm_score
                feedback.append(f"VLM Process Verification: {vlm_score}/20 pts.")
        else:
            feedback.append("VLM Verification: No frames available.")
    except Exception as e:
        logger.warning(f"VLM execution failed: {e}")

    # Final determination
    passed = score >= 70 and math_score > 0
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }