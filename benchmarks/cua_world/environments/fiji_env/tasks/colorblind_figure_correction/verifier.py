#!/usr/bin/env python3
"""
Verifier for colorblind_figure_correction task.
Checks if the user correctly converted a Red/Green composite to Magenta/Green
and flattened it to RGB.

Criteria:
1. Output file exists.
2. Output file is RGB (not a stack).
3. Output Green channel correlates with Input Channel 2 (Green).
4. Output Red channel correlates with Input Channel 1 (Red).
5. Output Blue channel correlates with Input Channel 1 (Red) -> Proves Magenta usage.
   (Magenta = Red + Blue).
"""

import json
import os
import tempfile
import logging
import numpy as np
from PIL import Image

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_colorblind_figure_correction(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # File paths
    input_remote = "/home/ga/Fiji_Data/raw/composite/unsafe_composite.tif"
    output_remote = "/home/ga/Fiji_Data/results/figures/accessible_composite.png"
    proof_remote = "/home/ga/Fiji_Data/results/figures/deuteranopia_proof.png"
    result_json_remote = "/tmp/task_result.json"

    # Create temp files
    tmp_input = tempfile.NamedTemporaryFile(delete=False, suffix=".tif").name
    tmp_output = tempfile.NamedTemporaryFile(delete=False, suffix=".png").name
    tmp_proof = tempfile.NamedTemporaryFile(delete=False, suffix=".png").name
    tmp_json = tempfile.NamedTemporaryFile(delete=False, suffix=".json").name

    files_to_clean = [tmp_input, tmp_output, tmp_proof, tmp_json]

    score = 0
    feedback = []
    
    try:
        # 1. Get JSON result for timestamps
        try:
            copy_from_env(result_json_remote, tmp_json)
            with open(tmp_json, 'r') as f:
                res_data = json.load(f)
        except Exception as e:
            return {"passed": False, "score": 0, "feedback": f"Failed to retrieve task metadata: {e}"}

        # Check existence
        if not res_data.get("accessible_exists"):
            return {"passed": False, "score": 0, "feedback": "Output file 'accessible_composite.png' not found."}
        
        score += 10
        feedback.append("Output file exists.")

        # Check timestamps
        task_start = res_data.get("task_start", 0)
        if res_data.get("accessible_mtime", 0) <= task_start:
             feedback.append("Warning: Output file timestamp suggests it wasn't created during this task session.")
        else:
             score += 5
             feedback.append("Output created during task.")

        # 2. Retrieve Images
        try:
            copy_from_env(input_remote, tmp_input)
            copy_from_env(output_remote, tmp_output)
            # Try proof, but it's optional for main image analysis
            try:
                copy_from_env(proof_remote, tmp_proof)
                has_proof = True
            except:
                has_proof = False
        except Exception as e:
            return {"passed": False, "score": score, "feedback": f"Failed to retrieve image files: {e}"}

        # 3. Analyze Image Structure
        try:
            img_in = Image.open(tmp_input)
            img_out = Image.open(tmp_output)
        except Exception as e:
            return {"passed": False, "score": score, "feedback": f"Failed to open images: {e}"}

        # Check RGB format
        if img_out.mode != 'RGB':
            feedback.append(f"Output image is {img_out.mode}, expected RGB.")
            # Penalize, but continue analysis if possible
        else:
            score += 15
            feedback.append("Output image is valid RGB.")

        # 4. Correlation Analysis
        # Input is likely a multi-page TIFF (stack)
        # We need to extract the two channels
        in_ch1 = None
        in_ch2 = None
        
        # Handle input stack
        try:
            img_in.seek(0)
            in_ch1 = np.array(img_in.convert('L'), dtype=float)
            img_in.seek(1)
            in_ch2 = np.array(img_in.convert('L'), dtype=float)
        except Exception:
             return {"passed": False, "score": score, "feedback": "Input image did not have 2 channels as expected."}

        # Resize output to match input if needed (though they should match)
        if img_out.size != img_in.size:
             img_out = img_out.resize(img_in.size)
             feedback.append("Resized output to match input dimensions.")

        out_arr = np.array(img_out, dtype=float)
        out_r = out_arr[:,:,0]
        out_g = out_arr[:,:,1]
        out_b = out_arr[:,:,2]

        # Calculate Correlations
        def get_corr(a, b):
            return np.corrcoef(a.flatten(), b.flatten())[0, 1]

        # Check Green Integrity: Output Green vs Input Ch2
        corr_g_ch2 = get_corr(out_g, in_ch2)
        if corr_g_ch2 > 0.8:
            score += 30
            feedback.append(f"Green channel preserved correctly (corr={corr_g_ch2:.2f}).")
        else:
            feedback.append(f"Green channel mismatch (corr={corr_g_ch2:.2f}). Expected high correlation with Ch2.")

        # Check Magenta Conversion: 
        # Magenta = Red + Blue.
        # Output Red should correlate with Input Ch1
        # Output Blue should correlate with Input Ch1
        corr_r_ch1 = get_corr(out_r, in_ch1)
        corr_b_ch1 = get_corr(out_b, in_ch1)

        magenta_success = False
        if corr_r_ch1 > 0.8 and corr_b_ch1 > 0.8:
            score += 40
            magenta_success = True
            feedback.append(f"Magenta conversion successful (R-corr={corr_r_ch1:.2f}, B-corr={corr_b_ch1:.2f}).")
        else:
            feedback.append(f"Magenta conversion failed. R-corr={corr_r_ch1:.2f} (exp >0.8), B-corr={corr_b_ch1:.2f} (exp >0.8).")

        # 5. Check Proof (10 pts)
        if has_proof:
            try:
                img_proof = Image.open(tmp_proof)
                if img_proof.size == img_out.size and np.mean(np.abs(np.array(img_proof) - np.array(img_out))) > 10:
                    # Proof exists and is different from the source (simulation applied)
                    score += 10
                    feedback.append("Simulation proof exists and appears modified.")
                else:
                    feedback.append("Simulation proof exists but looks identical to composite (simulation not applied?).")
            except:
                feedback.append("Simulation proof file corrupted.")
        else:
            feedback.append("Simulation proof file not found.")

    except Exception as e:
        logger.error(f"Verification error: {e}")
        return {"passed": False, "score": score, "feedback": f"Verification system error: {e}"}
    finally:
        for f in files_to_clean:
            if os.path.exists(f):
                os.unlink(f)

    return {
        "passed": score >= 90,
        "score": score,
        "feedback": " ".join(feedback)
    }