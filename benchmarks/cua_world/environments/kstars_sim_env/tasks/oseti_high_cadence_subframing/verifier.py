#!/usr/bin/env python3
"""
Verifier for oseti_high_cadence_subframing task.

Occupation: Astronomer / Optical SETI Researcher
Context: Rapid response high-cadence imaging using subframed Region of Interest (ROI).

Criteria (100 pts total, pass >= 65):
1. Telescope Position (20 pts): Pointed near KIC 8462852 (Boyajian's Star)
2. Valid FITS Count (30 pts): ≥20 files, excluding seeded stale data (checked via mtime)
3. Subframing Correct (20 pts): FITS headers prove NAXIS1=512, NAXIS2=512
4. Exposure Time Correct (10 pts): FITS headers prove EXPTIME=1.0s
5. Reference Sky Capture (10 pts): Exists & created during task
6. Observation Log (10 pts): Exists & created during task
"""

import json
import base64
import os
import math
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# KIC 8462852 true coordinates
TARGET_RA = 20.1043   # hours (20h 06m 15.45s)
TARGET_DEC = 44.4568  # degrees (+44d 27m 24.6s)
COORD_TOL_ARCMIN = 30.0

def angular_separation_deg(ra1_h, dec1_deg, ra2_h, dec2_deg):
    ra1 = math.radians(ra1_h * 15.0)
    dec1 = math.radians(dec1_deg)
    ra2 = math.radians(ra2_h * 15.0)
    dec2 = math.radians(dec2_deg)
    cos_sep = (math.sin(dec1) * math.sin(dec2) +
               math.cos(dec1) * math.cos(dec2) * math.cos(ra1 - ra2))
    cos_sep = max(-1.0, min(1.0, cos_sep))
    return math.degrees(math.acos(cos_sep))

def verify_oseti_high_cadence_subframing(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System error: copy_from_env unavailable"}

    metadata = task_info.get('metadata', {})
    min_fits = metadata.get('min_fits_count', 20)
    req_naxis = metadata.get('required_naxis', 512)
    req_exptime = metadata.get('required_exptime', 1.0)

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

    # 1. Pre-process File Arrays to detect Anti-Gaming
    fits_files = result.get('fits_files', [])
    valid_time_fits = [f for f in fits_files if f.get('mtime', 0) > task_start and f.get('size', 0) > 1024]
    
    subframed_fits = [f for f in valid_time_fits if f.get('naxis1') == req_naxis and f.get('naxis2') == req_naxis]
    perfect_fits = [f for f in subframed_fits if abs(f.get('exptime', -1) - req_exptime) < 0.1]

    fits_count = len(perfect_fits)

    # 2. Evaluate Telescope Position (20 pts)
    try:
        final_ra = float(result.get('final_ra', -1))
        final_dec = float(result.get('final_dec', -999))
    except (ValueError, TypeError):
        final_ra, final_dec = -1.0, -999.0

    coord_ok = False
    if final_ra > 0 and final_dec > -900:
        sep_deg = angular_separation_deg(final_ra, final_dec, TARGET_RA, TARGET_DEC)
        sep_arcmin = sep_deg * 60.0
        if sep_arcmin <= COORD_TOL_ARCMIN:
            score += 20
            coord_ok = True
            feedback.append(f"Telescope pointed at target (sep {sep_arcmin:.1f}')")
        elif sep_arcmin <= COORD_TOL_ARCMIN * 3:
            score += 10
            feedback.append(f"Telescope near target area (sep {sep_arcmin:.1f}')")
        else:
            feedback.append(f"Telescope not at target (sep {sep_arcmin:.1f}')")
    else:
        feedback.append("Could not read telescope coordinates")

    # 3. Evaluate FITS Count against the requirement (30 pts)
    if len(valid_time_fits) >= min_fits:
        score += 30
        feedback.append(f"Captured {len(valid_time_fits)} new FITS frames")
    elif len(valid_time_fits) >= min_fits / 2:
        score += 15
        feedback.append(f"Captured {len(valid_time_fits)}/{min_fits} new FITS frames")
    elif len(valid_time_fits) >= 1:
        score += 5
        feedback.append(f"Only {len(valid_time_fits)} new FITS frame(s)")
    else:
        feedback.append("No new FITS images captured in the target directory")

    # 4. Evaluate Subframing (ROI constraint) Verification (20 pts)
    if len(valid_time_fits) > 0:
        ratio_subframed = len(subframed_fits) / len(valid_time_fits)
        if ratio_subframed >= 0.8:
            score += 20
            feedback.append(f"Frames correctly subframed ({req_naxis}x{req_naxis} ROI)")
        elif len(subframed_fits) > 0:
            score += 10
            feedback.append(f"Some frames subframed ({len(subframed_fits)}/{len(valid_time_fits)})")
        else:
            first_shape = f"{valid_time_fits[0].get('naxis1')}x{valid_time_fits[0].get('naxis2')}"
            feedback.append(f"Frames NOT subframed (e.g. read as {first_shape})")

    # 5. Evaluate Exposure Constraint Verification (10 pts)
    if len(subframed_fits) > 0:
        ratio_exptime = len(perfect_fits) / len(subframed_fits)
        if ratio_exptime >= 0.8:
            score += 10
            feedback.append(f"Exposure time correctly set to {req_exptime}s")
        else:
            feedback.append("Exposure time incorrect for most frames")

    # 6. Evaluate Reference Sky Capture (10 pts)
    if result.get('sky_capture_exists'):
        score += 10
        feedback.append("Reference sky capture produced")
    else:
        feedback.append("Reference sky capture missing")

    # 7. Evaluate Observation Log (10 pts)
    log_exists = result.get('log_exists', False)
    log_mtime = result.get('log_mtime', 0)
    if log_exists and log_mtime > task_start:
        score += 10
        feedback.append("Observation log created")
        
        # Look for target name evidence in log contents
        b64 = result.get('log_b64', '')
        if b64:
            text = base64.b64decode(b64).decode('utf-8', errors='ignore').upper()
            if 'KIC 8462852' in text or 'BOYAJIAN' in text:
                feedback.append("Observation log mentions target correctly")
    elif log_exists:
        feedback.append("Observation log has pre-task timestamp (gaming attempt)")
    else:
        feedback.append("Observation log missing")

    # Ensure crucial benchmarks are hit: At least 50% FITS files created + Correct location
    passed = (score >= 65) and coord_ok and (fits_count >= (min_fits * 0.5))

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }