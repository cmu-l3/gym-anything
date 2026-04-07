#!/usr/bin/env python3
"""
Verifier for the generate_finding_chart task.

Evaluates the agent's ability to manipulate FITS data and alter visual state (LUT inversion).
Verifies:
1. FITS crop exists and was created during the task (Anti-gaming).
2. FITS crop is EXACTLY 500x500 pixels.
3. FITS crop isn't empty space (std dev > threshold to confirm cluster was targeted).
4. PNG export exists and was created during the task.
5. PNG export is properly inverted (mean brightness > 128 indicating white background).
6. Trajectory frames show the process of cropping and saving in AstroImageJ (VLM).
"""

import json
import tempfile
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_finding_chart(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available."}

    # Extract metadata
    metadata = task_info.get('metadata', {})
    expected_width = metadata.get('expected_width', 500)
    expected_height = metadata.get('expected_height', 500)

    score = 0
    feedback_parts = []
    
    # -------------------------------------------------------------------------
    # 1. Retrieve the exported JSON telemetry from the container
    # -------------------------------------------------------------------------
    temp_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_json.name)
        with open(temp_json.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read exported results: {e}"}
    finally:
        if os.path.exists(temp_json.name):
            os.unlink(temp_json.name)

    logger.info(f"Verification telemetry: {json.dumps(result, indent=2)}")

    # -------------------------------------------------------------------------
    # 2. Programmatic Verification (FITS & PNG logic)
    # -------------------------------------------------------------------------
    fits_ok = False
    png_ok = False

    # Check FITS Output
    if result.get("fits_exists"):
        if result.get("fits_created_during_task"):
            score += 10
            feedback_parts.append("FITS file successfully created.")
            
            # Dimension check (Must be EXACTLY 500x500)
            shape = result.get("fits_shape", [])
            # Note: numpy shape is (height, width) so we check both
            if len(shape) >= 2 and shape[0] == expected_height and shape[1] == expected_width:
                score += 20
                feedback_parts.append("FITS crop dimensions are exactly 500x500.")
                
                # Content check (Verify they didn't just crop a dark empty corner)
                # The M12 core contains bright stars, so standard deviation should be significant.
                if result.get("fits_std", 0) > 200.0 or result.get("fits_max", 0) > 5000.0:
                    score += 15
                    feedback_parts.append("FITS content verifies cluster core was targeted.")
                    fits_ok = True
                else:
                    feedback_parts.append("FITS cropped region appears too dark/empty (Missed the cluster core?).")
            else:
                feedback_parts.append(f"FITS crop dimensions incorrect. Expected 500x500, got {shape}.")
        else:
            feedback_parts.append("FITS file exists but was NOT modified during the task (Stale/Pre-existing).")
    else:
        feedback_parts.append("FITS cropped file was not found.")

    # Check PNG Output
    if result.get("png_exists"):
        if result.get("png_created_during_task"):
            score += 10
            feedback_parts.append("PNG finding chart successfully created.")
            
            # Inversion Check
            # Astronomical images are overwhelmingly dark sky. Inverting the LUT makes the sky white.
            # A normal image has mean brightness < ~50. An inverted finding chart has mean > 180.
            mean_brightness = result.get("png_mean_brightness", 0)
            if mean_brightness > 128.0:
                score += 20
                feedback_parts.append(f"PNG finding chart correctly inverted (mean brightness {mean_brightness:.1f} > 128).")
                png_ok = True
            else:
                feedback_parts.append(f"PNG finding chart does NOT appear inverted (mean brightness {mean_brightness:.1f} < 128).")
        else:
            feedback_parts.append("PNG file exists but was NOT modified during the task (Stale/Pre-existing).")
    else:
        feedback_parts.append("PNG finding chart file was not found.")

    # -------------------------------------------------------------------------
    # 3. Vision Language Model (VLM) Trajectory Verification
    # -------------------------------------------------------------------------
    try:
        from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm
        frames = sample_trajectory_frames(traj, n=4)
        final_frame = get_final_screenshot(traj)
        
        prompt = (
            "Review these frames from a screen recording of an AstroImageJ session. "
            "Did the user perform the following workflow? "
            "1. Open an astronomical image. "
            "2. Select a square region and crop the image. "
            "3. Invert the image's color map (Lookup Table) so the background sky becomes white and the stars become black. "
            "Reply strictly with 'YES' if the workflow is clearly visible, or 'NO' if it is not."
        )
        
        vlm_response = query_vlm(images=frames + [final_frame], prompt=prompt)
        logger.info(f"VLM Response: {vlm_response}")
        
        if "YES" in vlm_response.upper():
            score += 25
            feedback_parts.append("VLM verified correct visual trajectory.")
            vlm_ok = True
        else:
            feedback_parts.append("VLM did not detect the expected AstroImageJ workflow.")
            vlm_ok = False
            
    except ImportError:
        logger.warning("VLM module not available. Awarding VLM points provisionally based on programmatic success.")
        if fits_ok and png_ok:
            score += 25
            vlm_ok = True
        else:
            vlm_ok = False
    except Exception as e:
        logger.error(f"Error during VLM verification: {e}")
        vlm_ok = False

    # -------------------------------------------------------------------------
    # 4. Final Scoring
    # -------------------------------------------------------------------------
    passed = fits_ok and png_ok and score >= 75
    
    return {
        "passed": passed,
        "score": score,
        "feedback": "\n".join(feedback_parts)
    }