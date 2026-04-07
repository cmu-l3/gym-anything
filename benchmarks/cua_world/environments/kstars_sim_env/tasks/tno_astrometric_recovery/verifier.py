#!/usr/bin/env python3
"""
Verifier for tno_astrometric_recovery task.

Context: Astrometric follow-up of 3 Trans-Neptunian Objects using specific dates and settings.

Criteria (100 pts total, pass >= 70):
1. Eris: >=3 FITS, 120s exposure, correct coords (20 pts)
2. Makemake: >=3 FITS, 120s exposure, correct coords (20 pts)
3. Haumea: >=3 FITS, 120s exposure, correct coords (20 pts)
4. Filter Usage: Luminance (Slot 1) verified from headers (15 pts)
5. Sky Capture: makemake_field.png > 50KB exists (10 pts)
6. Summary Report: Mentions targets and date (15 pts)
"""

import json
import base64
import os
import math
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def angular_separation_deg(ra1_deg, dec1_deg, ra2_deg, dec2_deg):
    """Return angular separation in degrees between two decimal degrees coordinates."""
    ra1 = math.radians(ra1_deg)
    dec1 = math.radians(dec1_deg)
    ra2 = math.radians(ra2_deg)
    dec2 = math.radians(dec2_deg)
    cos_sep = (math.sin(dec1) * math.sin(dec2) +
               math.cos(dec1) * math.cos(dec2) * math.cos(ra1 - ra2))
    cos_sep = max(-1.0, min(1.0, cos_sep))
    return math.degrees(math.acos(cos_sep))


def verify_tno_astrometric_recovery(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System error: copy_from_env unavailable"}

    metadata = task_info.get('metadata', {})
    targets = metadata.get('targets', {})
    req_exp = metadata.get('required_exposure_sec', 120)
    min_frames = metadata.get('min_fits_count', 3)
    coord_tol_arcmin = metadata.get('coordinate_tolerance_arcmin', 5.0)
    target_date = metadata.get('target_date', '2026-03-10')

    tmp = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", tmp.name)
        with open(tmp.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Could not read task result: {e}"}
    finally:
        if os.path.exists(tmp.name):
            os.unlink(tmp.name)

    score = 0
    feedback = []
    task_start = result.get('task_start', 0)

    fits_files = result.get('fits_files', [])
    valid_fits = [f for f in fits_files if f.get('mtime', 0) > task_start and f.get('size', 0) > 2048]

    # Verify per-target
    targets_verified = 0
    filter_correct_count = 0

    for target_name in ["Eris", "Makemake", "Haumea"]:
        target_info = targets.get(target_name, {})
        expected_ra = target_info.get('ra_deg', -1)
        expected_dec = target_info.get('dec_deg', -999)
        
        target_frames = [f for f in valid_fits if f.get('target') == target_name]
        
        correct_coords_and_exp = 0
        
        for f in target_frames:
            ra = f.get('ra_deg', -1)
            dec = f.get('dec_deg', -999)
            exp = f.get('exptime', 0)
            filt = f.get('filter', '').upper()
            
            # Filter check (Luminance or L or 1)
            if 'LUM' in filt or 'CLEAR' in filt or 'L' in filt:
                filter_correct_count += 1
            
            # Coordinate check
            if ra > 0 and dec > -900 and expected_ra > 0:
                sep_arcmin = angular_separation_deg(ra, dec, expected_ra, expected_dec) * 60.0
                if sep_arcmin <= coord_tol_arcmin and abs(exp - req_exp) < 1.0:
                    correct_coords_and_exp += 1

        if correct_coords_and_exp >= min_frames:
            score += 20
            targets_verified += 1
            feedback.append(f"{target_name}: {correct_coords_and_exp} valid frames (120s, accurate coords)")
        elif correct_coords_and_exp > 0:
            score += 10
            feedback.append(f"{target_name}: {correct_coords_and_exp}/{min_frames} valid frames")
        elif len(target_frames) > 0:
            feedback.append(f"{target_name}: frames found but failed coordinate/exposure checks")
        else:
            feedback.append(f"{target_name}: no valid frames found")

    # Filter Score (15 pts) - If a majority of the target frames used Luminance
    if filter_correct_count >= (targets_verified * min_frames * 0.5) and filter_correct_count > 0:
        score += 15
        feedback.append("Filter verified as Luminance")
    else:
        feedback.append("Filter could not be definitively verified as Luminance")

    # Sky Capture (10 pts)
    sky_exists = result.get('sky_capture_exists', False)
    sky_size = result.get('sky_capture_size', 0)
    if sky_exists and sky_size > 50000:  # > 50KB implies real image
        score += 10
        feedback.append("Makemake sky capture image created successfully")
    elif sky_exists:
        feedback.append("Sky capture image found but file size too small to be valid")
    else:
        feedback.append("Makemake sky capture image missing")

    # Summary Report (15 pts)
    report_exists = result.get('report_exists', False)
    report_mtime = result.get('report_mtime', 0)
    report_b64 = result.get('report_content_b64', '')
    
    if report_exists and report_mtime > task_start:
        try:
            report_text = base64.b64decode(report_b64).decode('utf-8', errors='ignore').upper()
            has_date = target_date.replace("-", "") in report_text.replace("-", "") or target_date in report_text
            has_targets = 'ERIS' in report_text and 'MAKEMAKE' in report_text and 'HAUMEA' in report_text
            
            if has_date and has_targets:
                score += 15
                feedback.append("Summary report contains targets and correct date")
            elif has_targets:
                score += 8
                feedback.append("Summary report missing requested date context")
            else:
                score += 5
                feedback.append("Summary report exists but missing required targets/details")
        except Exception:
            feedback.append("Failed to decode summary report text")
    else:
        feedback.append("Summary report missing or not updated during task")

    passed = score >= 70 and targets_verified >= 2
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }