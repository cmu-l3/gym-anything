#!/usr/bin/env python3
"""
Verifier for Emission Line Ratio Map task.

Checks:
1. File Creation: Checks that FITS and PNG files were created during the task.
2. Image Math Verification: Divides the original [SII] by H-alpha FITS to compute
   the ground truth ratio map. Validates the agent's array matches this exact calculation.
3. Precision Verification: Verifies the resulting FITS is saved as a 32-bit float array.
4. Visualization Verification: Ensures the exported PNG has applied a false-color LUT 
   (i.e., not grayscale).
5. Workflow Verification (VLM): Confirms trajectory screenshots show the Image Calculator UI.
"""

import os
import sys
import json
import logging
import tempfile
import numpy as np

# Ensure required libraries are present
try:
    from astropy.io import fits
    from PIL import Image
except ImportError:
    import subprocess
    subprocess.check_call([sys.executable, "-m", "pip", "install", "-q", "astropy", "pillow"])
    from astropy.io import fits
    from PIL import Image

from gym_anything.vlm import sample_trajectory_frames, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_ratio_map(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_fits = metadata.get('expected_fits')
    expected_png = metadata.get('expected_png')
    sii_source = metadata.get('original_sii_source')
    ha_source = metadata.get('original_ha_source')

    score = 0
    feedback = []

    # 1. Read JSON result
    result = {}
    temp_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_json.name)
        with open(temp_json.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Could not read task export: {e}"}
    finally:
        if os.path.exists(temp_json.name):
            os.unlink(temp_json.name)

    fits_exists = result.get("fits_exists", False)
    png_exists = result.get("png_exists", False)
    fits_created = result.get("fits_created_during_task", False)
    png_created = result.get("png_created_during_task", False)

    if fits_exists and fits_created:
        score += 10
        feedback.append("FITS file successfully created.")
    elif fits_exists:
        feedback.append("FITS file exists but was not created during task (Anti-gaming flag).")
    else:
        feedback.append("FITS file was not saved to the correct location.")

    if png_exists and png_created:
        score += 10
        feedback.append("PNG visualization successfully created.")
    elif png_exists:
        feedback.append("PNG file exists but was not created during task.")
    else:
        feedback.append("PNG visualization was not saved.")

    # 2 & 3. Programmatic check of FITS Array Mathematics & Precision
    if fits_exists and fits_created:
        temp_sii = tempfile.NamedTemporaryFile(delete=False, suffix='.fits')
        temp_ha = tempfile.NamedTemporaryFile(delete=False, suffix='.fits')
        temp_agent = tempfile.NamedTemporaryFile(delete=False, suffix='.fits')
        
        try:
            copy_from_env(sii_source, temp_sii.name)
            copy_from_env(ha_source, temp_ha.name)
            copy_from_env(expected_fits, temp_agent.name)
            
            sii_data = fits.getdata(temp_sii.name).astype(float)
            ha_data = fits.getdata(temp_ha.name).astype(float)
            
            with fits.open(temp_agent.name) as hdul:
                agent_data = hdul[0].data
                agent_dtype = agent_data.dtype if agent_data is not None else None

            if agent_data is not None:
                # Check 32-bit precision
                if agent_dtype.kind == 'f':
                    score += 10
                    feedback.append("FITS preserved floating-point precision (32-bit float).")
                else:
                    feedback.append(f"Precision lost! Agent saved FITS as {agent_dtype} instead of float. Missed '32-bit result' checkbox.")

                # Compute true ratios
                valid_mask = (ha_data != 0) & ~np.isnan(ha_data) & ~np.isnan(sii_data)
                true_ratio = np.zeros_like(sii_data)
                true_ratio[valid_mask] = sii_data[valid_mask] / ha_data[valid_mask]
                
                # Check for reversed logic
                valid_rev_mask = (sii_data != 0) & ~np.isnan(sii_data) & ~np.isnan(ha_data)
                reversed_ratio = np.zeros_like(ha_data)
                reversed_ratio[valid_rev_mask] = ha_data[valid_rev_mask] / sii_data[valid_rev_mask]
                
                # Evaluate difference
                if agent_data.shape == true_ratio.shape:
                    diff_true = np.nanmean(np.abs(agent_data[valid_mask] - true_ratio[valid_mask]))
                    diff_rev = np.nanmean(np.abs(agent_data[valid_rev_mask] - reversed_ratio[valid_rev_mask]))
                    
                    if agent_dtype.kind == 'f':
                        if diff_true < 1e-4:
                            score += 30
                            feedback.append("Mathematical ratio strictly matches [SII]/H-alpha.")
                        elif diff_rev < 1e-4:
                            score += 10
                            feedback.append("Math logic reversed (divided H-alpha by [SII]).")
                        else:
                            feedback.append(f"FITS data does not match ratio calculation (Mean err: {diff_true:.4f}).")
                    else:
                        # If integer, compare against truncated math
                        truncated_true = true_ratio.astype(int)
                        if np.nanmean(np.abs(agent_data[valid_mask] - truncated_true[valid_mask])) < 1.0:
                            score += 15
                            feedback.append("Mathematical ratio matches [SII]/H-alpha, but suffered integer truncation.")
                        else:
                            feedback.append("Math logic incorrect or obscured by severe truncation.")
                else:
                    feedback.append("Agent FITS array dimensions do not match the source images.")

        except Exception as e:
            feedback.append(f"Error evaluating FITS data: {e}")
        finally:
            for tf in [temp_sii, temp_ha, temp_agent]:
                if os.path.exists(tf.name):
                    os.unlink(tf.name)

    # 4. Programmatic Check of PNG Visualization (False Color)
    if png_exists and png_created:
        temp_png = tempfile.NamedTemporaryFile(delete=False, suffix='.png')
        try:
            copy_from_env(expected_png, temp_png.name)
            img = Image.open(temp_png.name).convert('RGB')
            arr = np.array(img)
            
            # Grayscale images have identical R, G, and B channels
            is_grayscale = np.all(arr[:, :, 0] == arr[:, :, 1]) and np.all(arr[:, :, 1] == arr[:, :, 2])
            
            if not is_grayscale:
                score += 15
                feedback.append("PNG successfully applied a false-color LUT.")
            else:
                feedback.append("PNG is grayscale; failed to apply a color Lookup Table.")
                
        except Exception as e:
            feedback.append(f"Error evaluating PNG: {e}")
        finally:
            if os.path.exists(temp_png.name):
                os.unlink(temp_png.name)

    # 5. Workflow Verification with VLM
    try:
        frames = sample_trajectory_frames(traj, n=5)
        if frames:
            prompt = (
                "Review these trajectory screenshots from AstroImageJ. "
                "1. Is the 'Image Calculator' window clearly visible at some point being configured to divide two images? "
                "2. Is the Brightness/Contrast window or a colored Look-Up Table (LUT) visible in the workflow? "
                "Answer 'YES' if you see the Image Calculator window, otherwise 'NO'."
            )
            vlm_response = query_vlm(images=frames, prompt=prompt)
            if "YES" in vlm_response.upper():
                score += 25
                feedback.append("VLM verified Image Calculator usage in trajectory.")
            else:
                feedback.append("VLM did not detect Image Calculator UI in trajectory frames.")
    except Exception as e:
        feedback.append(f"VLM verification error: {e}")

    # Final logic
    key_criteria_met = fits_created and png_created
    passed = score >= 65 and key_criteria_met

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }