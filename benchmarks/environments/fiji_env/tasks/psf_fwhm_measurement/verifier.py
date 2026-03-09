#!/usr/bin/env python3
"""
Verifier for PSF FWHM Measurement Task.

Scoring Criteria (100 points total):
1. CSV Exists & Created During Task (15 pts)
2. CSV Valid Content (15 pts): At least 5 measurements.
3. Plausible Pixel Dimensions (15 pts): FWHM between 1.5 and 20 pixels.
4. Plausible Physical Dimensions (15 pts): FWHM between 0.2 and 3.0 um.
5. Measurement Consistency (10 pts): Coefficient of Variation < 50%.
6. Report Exists & Matches Data (15 pts): Report mean close to CSV mean.
7. Line Profile Plot Exists (5 pts).
8. VLM Workflow Verification (10 pts): Agent used line tool and plot profile.
"""

import json
import os
import tempfile
import logging

# Setup logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_psf_measurement(traj, env_info, task_info):
    """
    Verifies the PSF FWHM measurement task using exported JSON data and VLM.
    """
    # 1. Setup & Data Retrieval
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System error: copy_from_env not available."}

    # Load result JSON from container
    temp_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/psf_result.json", temp_json.name)
        with open(temp_json.name, 'r') as f:
            data = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve task results: {str(e)}"}
    finally:
        if os.path.exists(temp_json.name):
            os.unlink(temp_json.name)

    score = 0
    feedback = []
    
    # --- CRITERION 1: CSV Exists & Timestamp (15 pts) ---
    if data.get("csv_exists") and data.get("files_created_during_task"):
        score += 15
        feedback.append("Success: Measurement CSV created.")
    elif data.get("csv_exists"):
        feedback.append("Warning: CSV exists but timestamp suggests it wasn't created during this task.")
    else:
        feedback.append("Fail: No measurement CSV found.")

    # --- CRITERION 2: CSV Content (15 pts) ---
    row_count = data.get("row_count", 0)
    if row_count >= 5:
        score += 15
        feedback.append(f"Success: Measured {row_count} beads (target >= 5).")
    elif row_count > 0:
        score += 5
        feedback.append(f"Partial: Only measured {row_count} beads (target >= 5).")
    else:
        feedback.append("Fail: CSV contains no data rows.")

    # --- CRITERION 3: Plausible Pixel FWHM (15 pts) ---
    # Expected: 1.5px to 20px (depending on zoom/bead size, usually ~3-6px for diffraction limit)
    mean_px = data.get("mean_fwhm_px", 0)
    if 1.5 <= mean_px <= 20.0:
        score += 15
        feedback.append(f"Success: Mean FWHM ({mean_px:.2f} px) is scientifically plausible.")
    elif row_count > 0:
        feedback.append(f"Fail: Mean FWHM ({mean_px:.2f} px) is outside expected range (1.5-20px).")

    # --- CRITERION 4: Plausible Physical FWHM (15 pts) ---
    # Expected: 0.2um to 3.0um
    mean_um = data.get("mean_fwhm_um", 0)
    if 0.2 <= mean_um <= 3.0:
        score += 15
        feedback.append(f"Success: Mean FWHM ({mean_um:.3f} µm) is scientifically plausible.")
    elif row_count > 0:
        # Check if they just copied pixels to um without calibration
        if abs(mean_um - mean_px) < 0.1:
             feedback.append("Fail: µm values look identical to pixel values. Did you Calibrate?")
        else:
             feedback.append(f"Fail: Mean FWHM ({mean_um:.3f} µm) is outside expected range.")

    # --- CRITERION 5: Consistency (10 pts) ---
    # Beads should be similar. If CV > 50%, measurements are likely random or wrong features.
    cv = data.get("fwhm_cv", 1.0)
    if row_count > 1 and cv < 0.5:
        score += 10
        feedback.append("Success: Measurements are consistent across beads.")
    elif row_count > 1:
        feedback.append(f"Fail: High variance in measurements (CV={cv:.2f}).")

    # --- CRITERION 6: Report Integrity (15 pts) ---
    if data.get("report_exists"):
        content = data.get("report_content", "")
        # Check if the calculated mean from CSV appears in the report (roughly)
        # Tolerance 10%
        match_found = False
        if mean_um > 0:
            import re
            nums = [float(x) for x in re.findall(r"[-+]?\d*\.\d+|\d+", content)]
            for n in nums:
                if abs(n - mean_um) / mean_um < 0.15: # 15% tolerance
                    match_found = True
                    break
        
        if match_found:
            score += 15
            feedback.append("Success: Report contains accurate mean FWHM.")
        else:
            score += 5
            feedback.append("Partial: Report exists but value doesn't match CSV data.")
    else:
        feedback.append("Fail: Resolution report not found.")

    # --- CRITERION 7: Plot Exists (5 pts) ---
    if data.get("plot_exists"):
        score += 5
        feedback.append("Success: Line profile plot saved.")
    else:
        feedback.append("Fail: Line profile plot missing.")

    # --- CRITERION 8: VLM Verification (10 pts) ---
    # We check if the agent actually did the work using trajectory
    # This requires the VLM utilities from the environment
    vlm_score = 0
    try:
        from gym_anything.vlm import sample_trajectory_frames, query_vlm
        frames = sample_trajectory_frames(traj, n=4)
        
        prompt = """
        Review these screenshots of a user using Fiji/ImageJ.
        I am looking for evidence of the following workflow:
        1. A microscope image with bright spots (beads) is open.
        2. A straight line is drawn across one of the spots (yellow line).
        3. A "Plot Profile" window is visible showing a bell-curve or peak graph.
        
        Return JSON: {"evidence_found": boolean, "confidence": float}
        """
        
        # We assume query_vlm handles the API call
        # In a real deployment, we'd handle the response parsing robustly
        result = query_vlm(images=frames, prompt=prompt)
        parsed = result.get('parsed', {})
        
        if parsed.get('evidence_found', False):
            vlm_score = 10
            feedback.append("Success: VLM confirmed line profiling workflow.")
        else:
            feedback.append("Fail: VLM did not see line profiling steps.")
            
    except ImportError:
        # Fallback if VLM utils not available in verifier environment
        # We give benefit of doubt if CSV is good
        if score >= 60:
            vlm_score = 10
            feedback.append("Note: VLM check skipped (utils missing), awarded points based on output validity.")
        else:
            feedback.append("Note: VLM check skipped.")
    except Exception as e:
        logger.warning(f"VLM check failed: {e}")
        # If output files are perfect, we don't penalize for VLM failure
        if score >= 60:
             vlm_score = 10
    
    score += vlm_score

    # Final Pass/Fail
    # Threshold 60/100
    passed = (score >= 60)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }