#!/usr/bin/env python3
"""
Verifier for PSF FWHM Measurement task.

Verifies:
1. File format and content
2. Accuracy of mean FWHM against ground truth (Python fitted)
3. Computations (arcsec conversion, recommended aperture)
4. VLM verification of trajectory ensuring legitimate interactions
"""

import json
import tempfile
import os
import re
import logging

try:
    from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot
except ImportError:
    pass

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

TRAJECTORY_PROCESS_PROMPT = """You are analyzing a sequence of screenshots from an agent measuring stellar PSF FWHM in AstroImageJ.

The images are sampled chronologically.

For successful FWHM measurement, the agent should:
1. Have the AstroImageJ application open with a FITS image loaded.
2. Interact with the image to measure stars.
3. Evidence of this includes: line profiles (graphs) drawn across stars, radial profile plots, aperture circles on stars, or the Results window showing Width/FWHM columns.
4. No error dialogs blocking the workflow.

Assess:
1. IMAGE_INTERACTION: Is the FITS image displayed and interacted with (contrast adjusted, cursors/ROIs drawn)?
2. MEASUREMENT_EVIDENCE: Is there evidence of profile plots, measurement tools, or aperture overlays on stars?
3. NO_ERRORS: Are there any crash dialogs or error messages?

Respond in JSON format:
{
    "image_interaction": true/false,
    "measurement_evidence": true/false,
    "no_errors": true/false,
    "confidence": "low"/"medium"/"high",
    "observations": "describe the workflow progression"
}
"""

def _vlm_query(query_vlm, prompt, images=None):
    if not query_vlm or not images: 
        return None
    try:
        res = query_vlm(prompt=prompt, images=images)
        if res.get("success"):
            return res.get("parsed", {})
    except Exception as e:
        logger.warning(f"VLM query failed: {e}")
    return None

def verify_measure_psf_fwhm(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    score = 0
    feedback = []
    
    # 1. Fetch JSON result
    result = {}
    try:
        temp = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        copy_from_env("/tmp/task_result.json", temp.name)
        with open(temp.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}
    finally:
        if os.path.exists(temp.name): os.unlink(temp.name)

    # 2. Fetch Ground Truth
    gt = {}
    try:
        temp_gt = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        copy_from_env("/tmp/fwhm_ground_truth.json", temp_gt.name)
        with open(temp_gt.name, 'r') as f:
            gt = json.load(f)
    except Exception as e:
        logger.warning(f"Could not load GT: {e}")
    finally:
        if os.path.exists(temp_gt.name): os.unlink(temp_gt.name)

    expected_fwhm = gt.get('median_fwhm_pixels', 4.5)
    plate_scale = gt.get('plate_scale', 0.25)
    
    file_exists = result.get('file_exists', False)
    content = result.get('file_content', '')
    
    if not file_exists:
        return {"passed": False, "score": 0, "feedback": "Results file fwhm_results.txt not found."}
        
    score += 10
    feedback.append("Results file exists.")
    
    # Extract stars and FWHMs
    lines = content.split('\n')
    stars_measured = 0
    fwhms = []
    
    for line in lines:
        line = line.strip()
        if line.startswith('#') or not line:
            continue
        parts = re.split(r'\s+|,', line)
        nums = []
        for p in parts:
            try:
                nums.append(float(p))
            except:
                pass
        # Expect at least x, y, fwhm
        if len(nums) >= 3:
            fwhm_val = nums[-1]
            if 1.0 <= fwhm_val <= 50.0:  # Reasonableness check
                fwhms.append(fwhm_val)
                stars_measured += 1
                
    if stars_measured >= 5:
        score += 10
        feedback.append(f"Measured {stars_measured} stars.")
    elif stars_measured > 0:
        score += 5
        feedback.append(f"Measured {stars_measured} stars (expected >= 5).")
        
    if len(fwhms) > 0 and len(set(fwhms)) > 1:
        score += 10
        feedback.append("Individual FWHMs look reasonable and varied.")

    # Parse Summary Values
    mean_fwhm_match = re.search(r'Mean_FWHM_pixels:\s*([0-9.]+)', content, re.IGNORECASE)
    arcsec_match = re.search(r'Mean_FWHM_arcsec:\s*([0-9.]+)', content, re.IGNORECASE)
    aperture_match = re.search(r'Recommended_aperture_radius_pixels:\s*([0-9.]+)', content, re.IGNORECASE)
    
    reported_mean = None
    if mean_fwhm_match:
        try:
            reported_mean = float(mean_fwhm_match.group(1))
        except:
            pass
            
    if reported_mean is None and len(fwhms) > 0:
        reported_mean = sum(fwhms) / len(fwhms)
        
    # Check Accuracy
    if reported_mean is not None:
        diff_pct = abs(reported_mean - expected_fwhm) / expected_fwhm
        if diff_pct <= 0.15:
            score += 25  # 20 + 5 bonus
            feedback.append(f"Mean FWHM highly accurate ({reported_mean:.2f}px vs expected {expected_fwhm:.2f}px).")
        elif diff_pct <= 0.30:
            score += 20
            feedback.append(f"Mean FWHM accurate ({reported_mean:.2f}px).")
        else:
            feedback.append(f"Mean FWHM out of tolerance ({reported_mean:.2f}px vs expected {expected_fwhm:.2f}px).")
            
        # Check arcsec conversion
        if arcsec_match:
            reported_arcsec = float(arcsec_match.group(1))
            expected_arcsec = reported_mean * plate_scale
            if abs(reported_arcsec - expected_arcsec) <= 0.05:
                score += 10
                feedback.append("Arcsec conversion correct.")
                
        # Check aperture recommendation
        if aperture_match:
            reported_aperture = float(aperture_match.group(1))
            if 2.0 * reported_mean <= reported_aperture <= 3.5 * reported_mean:
                score += 10
                feedback.append(f"Recommended aperture ({reported_aperture}) is reasonable.")
            else:
                feedback.append(f"Recommended aperture ({reported_aperture}) is not 2x-3.5x FWHM.")

    # VLM Checks
    query_vlm = env_info.get('query_vlm')
    if query_vlm:
        try:
            frames = sample_trajectory_frames(traj, n=4)
            final = get_final_screenshot(traj)
            images = frames + [final] if final else frames
            
            vlm_res = _vlm_query(query_vlm, TRAJECTORY_PROCESS_PROMPT, images=images)
            if vlm_res:
                if vlm_res.get('image_interaction'):
                    score += 10
                    feedback.append("VLM: Image interaction verified.")
                if vlm_res.get('measurement_evidence'):
                    score += 10
                    feedback.append("VLM: Measurement evidence verified.")
                if vlm_res.get('no_errors', True):
                    score += 5
                    feedback.append("VLM: No blocking errors.")
        except Exception as e:
            logger.warning(f"VLM verification error: {e}")

    passed = score >= 60 and file_exists and (reported_mean is not None and abs(reported_mean - expected_fwhm) / expected_fwhm <= 0.30)
    
    return {
        "passed": passed,
        "score": min(score, 100),
        "feedback": " | ".join(feedback)
    }