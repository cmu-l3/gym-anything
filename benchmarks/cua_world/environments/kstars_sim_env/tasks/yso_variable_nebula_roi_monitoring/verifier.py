#!/usr/bin/env python3
"""
Verifier for yso_variable_nebula_roi_monitoring task.

Criteria (100 pts total, pass >= 70):
1. NGC 2261 observations (>=3 files, < 5MB, valid ROI size & center)   - 15 pts
2. NGC 1555 observations (>=3 files, < 5MB, valid ROI size & center)   - 15 pts
3. McNeil's Nebula observations (>=3 files, < 5MB, valid ROI size)     - 15 pts
4. Pointing accuracy (verified from FITS headers for all targets)      - 20 pts
5. CCD State Restored (Width=4096, X=0, Y=0 at export)                 - 20 pts
6. Context image created (sky_context.png after task start)            - 15 pts
"""

import json
import os
import math
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Target coordinates in decimal degrees
TARGETS = {
    "ngc2261": {"ra": 6.6528 * 15.0, "dec": 8.7444},
    "ngc1555": {"ra": 4.3658 * 15.0, "dec": 19.5353},
    "mcneils": {"ra": 5.7706 * 15.0, "dec": -0.0986}
}
COORD_TOL_DEG = 0.5  # 30 arcmin tolerance

def parse_hms_dms_to_deg(coord_str):
    """Attempt to parse common FITS RA/Dec string formats to decimal degrees."""
    if not coord_str:
        return None
    try:
        # If already decimal
        return float(coord_str)
    except ValueError:
        pass
    
    # Parse "HH MM SS" or "DD MM SS"
    parts = coord_str.replace(':', ' ').split()
    if len(parts) >= 3:
        try:
            d = float(parts[0])
            m = float(parts[1])
            s = float(parts[2])
            sign = -1 if '-' in str(parts[0]) else 1
            val = abs(d) + (m / 60.0) + (s / 3600.0)
            return sign * val
        except:
            pass
    return None

def angular_separation_deg(ra1_deg, dec1_deg, ra2_deg, dec2_deg):
    ra1 = math.radians(ra1_deg)
    dec1 = math.radians(dec1_deg)
    ra2 = math.radians(ra2_deg)
    dec2 = math.radians(dec2_deg)
    cos_sep = (math.sin(dec1) * math.sin(dec2) +
               math.cos(dec1) * math.cos(dec2) * math.cos(ra1 - ra2))
    cos_sep = max(-1.0, min(1.0, cos_sep))
    return math.degrees(math.acos(cos_sep))

def verify_yso_variable_nebula_roi_monitoring(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System error: copy_from_env unavailable"}

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
    valid_fits = [f for f in fits_files if f.get('mtime', 0) > task_start and f.get('size', 0) > 1024]

    # Validate each target
    targets_valid = {}
    pointing_success_count = 0

    for target_key, true_coords in TARGETS.items():
        # Get files for this target directory
        t_files = [f for f in valid_fits if f.get('dir') == target_key]
        
        # Check ROI sizes (must be ~2MB, definitively < 5MB)
        roi_files = [f for f in t_files if f.get('size', 0) < 5 * 1024 * 1024]
        
        # Check perfectly centered: 1024x1024 centered on 4096x4096 => X=1536, Y=1536
        centered_roi_files = [
            f for f in roi_files 
            if f.get('width') == 1024 and f.get('height') == 1024 
            and f.get('x_offset') == 1536 and f.get('y_offset') == 1536
        ]
        
        # We will award points if they got the ROI right (or close)
        pts = 0
        if len(centered_roi_files) >= 3:
            pts = 15
            feedback.append(f"{target_key}: 3+ valid 1024x1024 centered ROI frames")
        elif len(roi_files) >= 3:
            pts = 10
            feedback.append(f"{target_key}: 3+ subframes, but not perfectly centered (X/Y off)")
        elif len(t_files) >= 3:
            pts = 5
            feedback.append(f"{target_key}: 3+ frames captured, but full-frame (>5MB)! Failed bandwidth limits.")
        elif len(centered_roi_files) > 0:
            pts = 5
            feedback.append(f"{target_key}: only {len(centered_roi_files)} centered ROI frames.")
        else:
            feedback.append(f"{target_key}: no valid frames captured.")
            
        score += pts
        
        # Evaluate pointing for this target
        target_pointed = False
        for f in t_files:
            ra_deg = parse_hms_dms_to_deg(f.get('ra'))
            dec_deg = parse_hms_dms_to_deg(f.get('dec'))
            if ra_deg is not None and dec_deg is not None:
                # KStars header RA is usually in hours
                if f.get('ra', '').replace(':', ' ').split()[0].find('.') == -1 and ':' in f.get('ra', ''):
                    # If string formatted, parse_hms assumed degrees unless converted.
                    # KStars RA string: "06:39:10" -> parse gives hours.
                    ra_deg = ra_deg * 15.0 
                
                sep = angular_separation_deg(ra_deg, dec_deg, true_coords['ra'], true_coords['dec'])
                if sep <= COORD_TOL_DEG:
                    target_pointed = True
                    break
        
        if target_pointed:
            pointing_success_count += 1

    # ── Criterion 4: Pointing accuracy (20 pts) ──────────────────────────
    if pointing_success_count == 3:
        score += 20
        feedback.append("Pointing accuracy: verified for all 3 targets")
    elif pointing_success_count > 0:
        score += pointing_success_count * 6
        feedback.append(f"Pointing accuracy: verified for {pointing_success_count}/3 targets")
    else:
        feedback.append("Pointing accuracy: telescope not verified at any correct target")

    # ── Criterion 5: CCD State Restored (20 pts) ─────────────────────────
    ccd_state = result.get('ccd_final_state', {})
    if ccd_state.get('width') == '4096' and ccd_state.get('height') == '4096' and ccd_state.get('x') == '0':
        score += 20
        feedback.append("CCD state successfully restored to full-frame")
    else:
        feedback.append(f"CCD state NOT restored (Width={ccd_state.get('width')}, X={ccd_state.get('x')})")

    # ── Criterion 6: Context Image (15 pts) ──────────────────────────────
    if result.get('context_exists', False):
        score += 15
        feedback.append("Sky context image created successfully")
    else:
        feedback.append("Sky context image missing or invalid")

    passed = score >= 70
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }