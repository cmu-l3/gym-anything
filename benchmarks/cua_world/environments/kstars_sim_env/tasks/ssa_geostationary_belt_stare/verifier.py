#!/usr/bin/env python3
"""
Verifier for ssa_geostationary_belt_stare task.

Criteria (100 pts total, pass >= 70):
1. FITS files generation: >=15 frames in correct directory. (20 pts)
2. Correct camera configuration: Exptime=30s, Filter=Luminance/Clear. (15 pts)
3. TRACKING DISABLED (Anti-Gaming & Core Objective): 
   Calculates RA drift between the first and last FITS frame. 
   Must drift significantly (>0.05 hours) confirming tracking was off. (35 pts)
4. Initial Slew Accuracy: First frame RA/Dec near 21h15m, -05deg15m. (10 pts)
5. Sky capture output exists. (10 pts)
6. SSA report exists. (10 pts)

CRITICAL: If Tracking is left ON, drift will be 0 and the agent will fail the
pass threshold, validating they properly executed the non-standard mode.
"""

import json
import base64
import os
import math
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

TARGET_RA = 21.25     # 21h 15m
TARGET_DEC = -5.25    # -05° 15'
DRIFT_THRESHOLD = 0.05  # minimum hours of RA drift expected across sequence


def parse_ra_to_hours(ra_str):
    if not ra_str:
        return -1.0
    ra_str = str(ra_str).strip()
    # Handle direct float
    try:
        val = float(ra_str)
        # If the simulator writes degrees instead of hours for some reason,
        # very high values indicate degrees. Assume standard string first.
        if val > 24.0:
            return val / 15.0
        return val
    except ValueError:
        pass
    
    # Handle "HH MM SS" or "HH:MM:SS"
    parts = ra_str.replace(':', ' ').split()
    try:
        if len(parts) >= 3:
            return float(parts[0]) + float(parts[1])/60.0 + float(parts[2])/3600.0
        return -1.0
    except:
        return -1.0


def parse_dec_to_degrees(dec_str):
    if not dec_str:
        return -999.0
    dec_str = str(dec_str).strip()
    try:
        return float(dec_str)
    except ValueError:
        pass
    
    parts = dec_str.replace(':', ' ').split()
    try:
        if len(parts) >= 3:
            sign = -1 if '-' in parts[0] else 1
            d = abs(float(parts[0]))
            m = float(parts[1])
            s = float(parts[2])
            return sign * (d + m/60.0 + s/3600.0)
        return -999.0
    except:
        return -999.0


def verify_ssa_geostationary_belt_stare(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System error: copy_from_env unavailable"}

    metadata = task_info.get('metadata', {})
    min_fits = metadata.get('min_fits_count', 15)
    req_exptime = metadata.get('required_exposure_sec', 30)

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
    # Valid frames only
    valid_fits = [f for f in fits_files if f.get('mtime', 0) > task_start and f.get('size', 0) > 2048]
    # Sort by creation time to analyze sequence
    valid_fits.sort(key=lambda x: x.get('mtime', 0))
    valid_count = len(valid_fits)

    # ── Criterion 1: File Generation (20 pts) ─────────────────────────
    if valid_count >= min_fits:
        score += 20
        feedback.append(f"Captured {valid_count} FITS images (target: {min_fits})")
    elif valid_count >= 5:
        score += 10
        feedback.append(f"Captured partial sequence: {valid_count}/{min_fits} images")
    else:
        feedback.append(f"Missing image sequence: only {valid_count} valid FITS images")

    # ── Criterion 2: Configuration Accuracy (15 pts) ──────────────────
    if valid_count > 0:
        exptime_ok = all(abs(f.get('exptime', -1) - req_exptime) < 1.0 for f in valid_fits)
        filters = [str(f.get('filter', '')).upper() for f in valid_fits]
        filter_ok = all('LUM' in filt or 'CLEAR' in filt or filt == 'L' for filt in filters)
        
        if exptime_ok and filter_ok:
            score += 15
            feedback.append("Exposure time and filter configured correctly")
        elif exptime_ok:
            score += 7
            feedback.append("Exposure time correct, but filter incorrect")
        elif filter_ok:
            score += 7
            feedback.append("Filter correct, but exposure time incorrect")
        else:
            feedback.append("Incorrect exposure time and filter")
    else:
        feedback.append("Cannot verify camera configuration without FITS files")

    # ── Criterion 3: Tracking Disabled / Drift (35 pts) ───────────────
    drift_score = 0
    if valid_count >= 2:
        first_ra = parse_ra_to_hours(valid_fits[0].get('ra'))
        last_ra = parse_ra_to_hours(valid_fits[-1].get('ra'))
        
        if first_ra >= 0 and last_ra >= 0:
            # RA drift analysis (Earth rotates 1 hr RA per hour time)
            # Take modulus to handle 24h wraparound just in case
            raw_drift = (last_ra - first_ra) % 24.0
            # If tracking is on, difference is exactly 0.
            if raw_drift >= DRIFT_THRESHOLD:
                drift_score = 35
                feedback.append(f"Tracking successfully disabled (RA drifted by {raw_drift:.3f} hrs)")
            elif raw_drift > 0.01:
                drift_score = 15
                feedback.append(f"Tracking off but drift was small ({raw_drift:.3f} hrs). Insufficient frames?")
            else:
                feedback.append(f"CRITICAL FAIL: Tracking left ON (RA drift {raw_drift:.4f} hrs < threshold)")
        else:
            feedback.append("Could not extract valid RA from FITS headers to verify tracking state")
    else:
        feedback.append("Not enough frames to verify coordinate drift")
    score += drift_score

    # ── Criterion 4: Initial Slew Accuracy (10 pts) ───────────────────
    if valid_count > 0:
        first_ra = parse_ra_to_hours(valid_fits[0].get('ra'))
        first_dec = parse_dec_to_degrees(valid_fits[0].get('dec'))
        
        if first_ra >= 0 and first_dec != -999.0:
            # Convert hours to degrees for distance
            ra_dist = abs(first_ra - TARGET_RA) * 15.0
            dec_dist = abs(first_dec - TARGET_DEC)
            dist_deg = math.sqrt(ra_dist**2 + dec_dist**2)
            
            if dist_deg < 1.0:
                score += 10
                feedback.append("Initial telescope slew accurate")
            elif dist_deg < 5.0:
                score += 5
                feedback.append(f"Initial slew near target (offset {dist_deg:.1f}°)")
            else:
                feedback.append(f"Initial slew incorrect (offset {dist_deg:.1f}°)")
    
    # ── Criterion 5: Sky Capture Output (10 pts) ──────────────────────
    sky_exists = result.get('sky_capture_exists', False)
    if sky_exists:
        score += 10
        feedback.append("Sky view capture created successfully")
    else:
        feedback.append("Sky view capture missing")

    # ── Criterion 6: SSA Report (10 pts) ──────────────────────────────
    report_exists = result.get('report_exists', False)
    report_mtime = result.get('report_mtime', 0)
    
    if report_exists and report_mtime > task_start:
        score += 10
        feedback.append("SSA report created during task")
    elif report_exists:
        score += 3
        feedback.append("SSA report exists but pre-dates task start")
    else:
        feedback.append("SSA report missing")

    # ── Final Determination ───────────────────────────────────────────
    # Must meet core objective of disabling tracking
    passed = (score >= 70) and (drift_score > 0)

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }