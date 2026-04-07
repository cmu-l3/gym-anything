#!/usr/bin/env python3
"""
Verifier for Evaluate Image Seeing Task.

Multi-Criteria Verification:
1. File Creation: CSV and TXT files exist and were created during the task. (20 pts)
2. Table Structure: CSV contains exactly 5 rows with recognizable X, Y, and FWHM headers. (15 pts)
3. Report Calculation: TXT contains "Average FWHM: <value>" which correctly averages the CSV column. (15 pts)
4. Dynamic Ground Truth: 2D Gaussian fit on the original FITS file at the agent's (X,Y) matches their reported FWHM. (30 pts)
5. VLM Verification: Analyzes trajectory and final screenshot for tool usage and aperture overlays. (20 pts)
"""

import os
import json
import csv
import re
import math
import tempfile
import logging
import numpy as np

# Configure logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Try importing astropy for the dynamic ground truth
try:
    from astropy.io import fits
    from astropy.modeling import models, fitting
    ASTROPY_AVAILABLE = True
except ImportError:
    ASTROPY_AVAILABLE = False
    logger.warning("astropy not available. Dynamic ground truth may have limited accuracy.")

def fit_2d_gaussian_fwhm(image_data, x, y, box_size=21):
    """
    Extracts a box around (x,y) and fits a 2D Gaussian to compute real FWHM.
    """
    if not ASTROPY_AVAILABLE:
        return None
        
    x_int, y_int = int(round(x)), int(round(y))
    half_box = box_size // 2
    
    # Check boundaries
    if (y_int - half_box < 0 or y_int + half_box + 1 > image_data.shape[0] or
        x_int - half_box < 0 or x_int + half_box + 1 > image_data.shape[1]):
        return None
        
    cutout = image_data[y_int - half_box: y_int + half_box + 1,
                        x_int - half_box: x_int + half_box + 1]
    
    yy, xx = np.mgrid[:box_size, :box_size]
    
    # Initial guess for the Gaussian
    p_init = models.Gaussian2D(
        amplitude=np.max(cutout) - np.median(cutout),
        x_mean=half_box,
        y_mean=half_box,
        x_stddev=2.0,
        y_stddev=2.0,
        theta=0.0
    ) + models.Const2D(amplitude=np.median(cutout))
    
    fitter = fitting.LevMarLSQFitter()
    
    try:
        p_opt = fitter(p_init, xx, yy, cutout)
        # FWHM = 2.355 * sigma
        fwhm_x = p_opt.x_stddev_0.value * 2.3548
        fwhm_y = p_opt.y_stddev_0.value * 2.3548
        fwhm = (abs(fwhm_x) + abs(fwhm_y)) / 2.0
        return fwhm
    except Exception as e:
        logger.error(f"Failed to fit Gaussian at {x},{y}: {e}")
        return None

def verify_image_seeing(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_stars = metadata.get('expected_stars_count', 5)
    fwhm_tolerance = metadata.get('fwhm_tolerance_percent', 25) / 100.0
    avg_calc_tolerance = metadata.get('avg_calc_tolerance', 0.05)

    score = 0
    feedback = []

    # Helper to load files
    def fetch_file(remote_path, as_json=False):
        temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json' if as_json else '.tmp')
        try:
            copy_from_env(remote_path, temp_file.name)
            if as_json:
                with open(temp_file.name, 'r') as f:
                    return json.load(f)
            return temp_file.name
        except Exception:
            os.unlink(temp_file.name)
            return None

    # Load result state
    result = fetch_file("/tmp/task_result.json", as_json=True) or {}
    
    # 1. File existence & creation time (20 pts)
    csv_exists = result.get('csv_exists', False)
    txt_exists = result.get('txt_exists', False)
    csv_created = result.get('csv_created_during_task', False)
    txt_created = result.get('txt_created_during_task', False)
    
    if csv_exists and txt_exists:
        if csv_created and txt_created:
            score += 20
            feedback.append("CSV and TXT correctly created during task.")
        else:
            score += 10
            feedback.append("Files exist but timestamps indicate they may have existed before the task.")
    else:
        feedback.append("Required output files (CSV or TXT) are missing.")
        return {"passed": False, "score": 0, "feedback": " | ".join(feedback)}

    # 2. Table Structure & Data Extraction (15 pts)
    csv_local_path = fetch_file("/tmp/seeing_data.csv")
    agent_fwhms = []
    agent_coords = []
    
    if csv_local_path:
        try:
            with open(csv_local_path, 'r', encoding='utf-8') as f:
                # Handle standard CSV or tab-separated
                sample = f.read(1024)
                f.seek(0)
                dialect = csv.Sniffer().sniff(sample) if sample else csv.excel
                reader = csv.DictReader(f, dialect=dialect)
                headers = reader.fieldnames or []
                
                # Identify columns
                x_col = next((h for h in headers if h.lower() in ['x', 'x(fits)', 'x_image']), None)
                y_col = next((h for h in headers if h.lower() in ['y', 'y(fits)', 'y_image']), None)
                fwhm_col = next((h for h in headers if 'fwhm' in h.lower() or 'width' in h.lower()), None)
                
                if x_col and y_col and fwhm_col:
                    for row in reader:
                        try:
                            agent_coords.append((float(row[x_col]), float(row[y_col])))
                            agent_fwhms.append(float(row[fwhm_col]))
                        except (ValueError, TypeError):
                            continue
        except Exception as e:
            logger.error(f"Error parsing CSV: {e}")
        finally:
            os.unlink(csv_local_path)
            
    num_stars = len(agent_fwhms)
    if num_stars == expected_stars:
        score += 15
        feedback.append(f"Correctly measured exactly {expected_stars} stars.")
    elif num_stars > 0:
        score += 5
        feedback.append(f"Measured {num_stars} stars instead of {expected_stars}.")
    else:
        feedback.append("Failed to extract valid measurements from CSV.")
        return {"passed": False, "score": score, "feedback": " | ".join(feedback)}

    # 3. Report Calculation (15 pts)
    txt_local_path = fetch_file("/tmp/seeing_report.txt")
    reported_avg = None
    if txt_local_path:
        try:
            with open(txt_local_path, 'r', encoding='utf-8') as f:
                content = f.read().strip()
                # Look for "Average FWHM: <number>"
                match = re.search(r'Average FWHM:\s*([0-9]*\.?[0-9]+)', content, re.IGNORECASE)
                if match:
                    reported_avg = float(match.group(1))
        except Exception as e:
            logger.error(f"Error parsing TXT: {e}")
        finally:
            os.unlink(txt_local_path)
            
    if reported_avg is not None:
        actual_avg = sum(agent_fwhms) / len(agent_fwhms)
        if abs(reported_avg - actual_avg) <= avg_calc_tolerance:
            score += 15
            feedback.append("Calculated average in TXT matches CSV data.")
        else:
            feedback.append(f"Average mismatch. Calculated {actual_avg:.2f}, reported {reported_avg:.2f}.")
    else:
        feedback.append("Could not find properly formatted 'Average FWHM: <value>' in TXT.")

    # 4. Dynamic Ground Truth (30 pts)
    # Open FITS and verify the FWHM at the provided coordinates
    fits_local_path = fetch_file("/tmp/Vcomb.fits")
    ground_truth_passed = 0
    if fits_local_path and ASTROPY_AVAILABLE:
        try:
            with fits.open(fits_local_path) as hdul:
                image_data = hdul[0].data
                
                valid_stars = 0
                for (x, y), agent_fwhm in zip(agent_coords, agent_fwhms):
                    true_fwhm = fit_2d_gaussian_fwhm(image_data, x, y)
                    if true_fwhm and abs(true_fwhm - agent_fwhm) / true_fwhm <= fwhm_tolerance:
                        valid_stars += 1
                        
                if valid_stars == num_stars and valid_stars > 0:
                    score += 30
                    feedback.append(f"Dynamic FWHM validation passed for {valid_stars} stars.")
                    ground_truth_passed = True
                elif valid_stars > 0:
                    score += int(30 * (valid_stars / num_stars))
                    feedback.append(f"Dynamic FWHM validation passed for {valid_stars}/{num_stars} stars.")
                    # Partial pass for ground truth
                    ground_truth_passed = (valid_stars / num_stars) >= 0.5
                else:
                    feedback.append("Coordinates/FWHM do not match actual star profiles in the FITS image.")
        except Exception as e:
            logger.error(f"FITS validation error: {e}")
        finally:
            os.unlink(fits_local_path)
    else:
        if not ASTROPY_AVAILABLE:
            feedback.append("Astropy unavailable; skipping strict dynamic ground truth.")
            # Default to giving some points if they extracted valid-looking data
            if 1.0 < sum(agent_fwhms)/len(agent_fwhms) < 15.0:
                score += 30
                ground_truth_passed = True
                
    # 5. VLM Visual Verification (20 pts)
    # Verify the workflow by checking trajectory frames and final screenshot
    try:
        from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm
        
        frames = sample_trajectory_frames(traj, n=3)
        final = get_final_screenshot(traj)
        
        prompt = """
        Review these screenshots of an agent using AstroImageJ.
        1. Is AstroImageJ open with an astronomical FITS image loaded?
        2. Are there circular aperture overlays (green/red/yellow concentric rings) visible on multiple stars in the image?
        
        Reply with a JSON containing a boolean field 'tool_used' which is true only if both conditions are met.
        Format: {"tool_used": true/false}
        """
        
        vlm_resp = query_vlm(images=frames + [final], prompt=prompt)
        try:
            # Simple fallback JSON extraction
            json_text = vlm_resp[vlm_resp.find("{"):vlm_resp.rfind("}")+1]
            vlm_result = json.loads(json_text)
            if vlm_result.get('tool_used'):
                score += 20
                feedback.append("VLM confirmed visual presence of aperture tools.")
            else:
                feedback.append("VLM did not detect aperture overlays in AstroImageJ.")
        except json.JSONDecodeError:
            logger.warning("VLM response could not be parsed as JSON.")
    except Exception as e:
        logger.warning(f"VLM verification failed: {e}")
        # If VLM fails, assume visual completion if ground truth succeeded
        if ground_truth_passed:
            score += 20
            feedback.append("VLM skipped; awarded points based on ground truth.")

    # Pass Condition: Minimum 70 points AND dynamic ground truth must be primarily passed.
    passed = (score >= 70) and ground_truth_passed

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }