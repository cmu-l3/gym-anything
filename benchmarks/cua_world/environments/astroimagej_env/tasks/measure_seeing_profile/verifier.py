#!/usr/bin/env python3
"""
Verifier for measure_seeing_profile task.

Verifies:
1. Agent exported CSV, PNG, and TXT files DURING the task.
2. The agent correctly measured a background empty sky region (Mean & StdDev check).
3. The agent extracted a reasonable FWHM value from a star.
4. Visual verification via VLM confirms a Seeing Profile was generated.
"""

import json
import os
import re
import csv
import tempfile
import logging
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_seeing_profile(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    fwhm_min = metadata.get('fwhm_min', 1.5)
    fwhm_max = metadata.get('fwhm_max', 8.0)
    mean_tol = metadata.get('mean_tolerance_pct', 15) / 100.0
    std_tol = metadata.get('stddev_tolerance_pct', 40) / 100.0

    score = 0
    feedback_parts = []
    
    # Define temp file paths for copy_from_env
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    temp_csv = tempfile.NamedTemporaryFile(delete=False, suffix='.csv')
    temp_txt = tempfile.NamedTemporaryFile(delete=False, suffix='.txt')

    try:
        # Load main result JSON
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result = json.load(f)
            
        file_info = result.get('files', {})
        gt = result.get('ground_truth', {})
        
        # ---------------------------------------------------------
        # Criterion 1: Profile Plot PNG Saved & VLM Verification (30 points)
        # ---------------------------------------------------------
        png_info = file_info.get('png', {})
        if png_info.get('exists') and png_info.get('created_during_task'):
            score += 15
            feedback_parts.append("Seeing profile PNG saved")
            
            # Use VLM to confirm the trajectory shows seeing profile generation
            frames = sample_trajectory_frames(traj, n=4)
            final = get_final_screenshot(traj)
            prompt = (
                "Review these trajectory frames from an AstroImageJ session. "
                "Did the user generate and view a 'Seeing Profile' or 'Radial Profile' plot? "
                "Look for a window containing a 2D bell-curve plot of a star and FWHM statistics. "
                "Reply with 'YES' if the profile plot window is visible in any frame, otherwise 'NO'."
            )
            vlm_response = query_vlm(images=frames + [final], prompt=prompt)
            if "YES" in vlm_response.upper():
                score += 15
                feedback_parts.append("VLM confirmed Seeing Profile interaction")
            else:
                feedback_parts.append("VLM did not detect Seeing Profile plot")
        else:
            feedback_parts.append("Missing seeing_profile.png")

        # ---------------------------------------------------------
        # Criterion 2: Background Stats CSV (50 points)
        # ---------------------------------------------------------
        csv_info = file_info.get('csv', {})
        csv_mean_accurate = False
        
        if csv_info.get('exists') and csv_info.get('created_during_task'):
            score += 15
            feedback_parts.append("Background stats CSV saved")
            
            try:
                copy_from_env("/tmp/background_stats.csv", temp_csv.name)
                # Parse CSV flexibly
                with open(temp_csv.name, 'r') as f:
                    content = f.read()
                    delimiter = ',' if ',' in content else '\t'
                    
                with open(temp_csv.name, 'r') as f:
                    reader = csv.DictReader(f, delimiter=delimiter)
                    rows = list(reader)
                    
                if rows:
                    row = rows[0]  # Take the first measurement
                    # Account for various header names in ImageJ
                    mean_val = None
                    std_val = None
                    
                    for k, v in row.items():
                        if k and 'mean' in k.lower():
                            mean_val = float(v)
                        if k and ('std' in k.lower() or 'dev' in k.lower()):
                            std_val = float(v)
                            
                    if mean_val is not None and gt.get('success'):
                        true_median = gt.get('true_bkg_median', 0)
                        if true_median > 0 and abs(mean_val - true_median) / true_median <= mean_tol:
                            score += 20
                            csv_mean_accurate = True
                            feedback_parts.append(f"Accurate sky Mean ({mean_val:.2f})")
                        else:
                            feedback_parts.append(f"Inaccurate sky Mean ({mean_val:.2f} vs True {true_median:.2f})")
                    else:
                        feedback_parts.append("Mean column missing from CSV")

                    if std_val is not None and gt.get('success'):
                        true_std = gt.get('true_bkg_std', 0)
                        if true_std > 0 and abs(std_val - true_std) / true_std <= std_tol:
                            score += 15
                            feedback_parts.append(f"Accurate sky StdDev ({std_val:.2f})")
                        else:
                            feedback_parts.append(f"Inaccurate sky StdDev ({std_val:.2f} vs True {true_std:.2f})")
                    else:
                        feedback_parts.append("StdDev column missing from CSV")
            except Exception as e:
                logger.error(f"Error parsing CSV: {e}")
                feedback_parts.append("Failed to parse CSV")
        else:
            feedback_parts.append("Missing background_stats.csv")

        # ---------------------------------------------------------
        # Criterion 3: Seeing Report TXT (20 points)
        # ---------------------------------------------------------
        txt_info = file_info.get('txt', {})
        if txt_info.get('exists') and txt_info.get('created_during_task'):
            try:
                copy_from_env("/tmp/seeing_report.txt", temp_txt.name)
                with open(temp_txt.name, 'r') as f:
                    content = f.read()
                
                match = re.search(r'FWHM:\s*([0-9.]+)', content, re.IGNORECASE)
                if match:
                    fwhm_val = float(match.group(1))
                    if fwhm_min <= fwhm_val <= fwhm_max:
                        score += 20
                        feedback_parts.append(f"Valid FWHM reported ({fwhm_val})")
                    else:
                        feedback_parts.append(f"FWHM out of expected range ({fwhm_val})")
                else:
                    feedback_parts.append("TXT file format incorrect (expected 'FWHM: [value]')")
            except Exception as e:
                logger.error(f"Error parsing TXT: {e}")
                feedback_parts.append("Failed to parse seeing_report.txt")
        else:
            feedback_parts.append("Missing seeing_report.txt")

    except Exception as e:
        logger.error(f"Error in verifier: {e}")
        return {"passed": False, "score": 0, "feedback": f"Verifier crash: {str(e)}"}
    finally:
        # Cleanup
        for p in [temp_result.name, temp_csv.name, temp_txt.name]:
            if os.path.exists(p):
                os.unlink(p)

    # ---------------------------------------------------------
    # Final Decision
    # ---------------------------------------------------------
    # Must get passing score AND successfully perform the accurate empty-sky measurement
    passed = (score >= 70) and csv_mean_accurate
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }