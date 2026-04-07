#!/usr/bin/env python3
"""
Verifier for wide_field_dark_nebula_survey task.

Occupation: Astrophotographer
Context: Wide-field surveying of Dark Nebulae. Requires modifying core INDI optics 
         parameters (Focal length and Aperture) to frame extended targets properly.

Criteria (100 pts total, pass >= 60):
1. FITS frames for B33 (Horsehead)                   - 15 pts
2. FITS frames for B143 (Barnard's E)                - 15 pts
3. FITS frames for B86 (Ink Spot)                    - 15 pts
4. Equipment Reconfiguration (Focal length & Apt)    - 25 pts
5. Contextual Sky Views generated                    - 15 pts
6. Survey Log creation                               - 15 pts
"""

import json
import base64
import os
import math
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

TARGETS = {
    'B33':  {'ra': 5.683,  'dec': -2.458},
    'B143': {'ra': 19.678, 'dec': 10.950},
    'B86':  {'ra': 18.050, 'dec': -27.866}
}

COORD_TOL_DEG = 1.0  # 1 degree tolerance since FOV is 15 degrees

def parse_hms(s):
    try:
        parts = str(s).replace(':', ' ').strip().split()
        return float(parts[0]) + float(parts[1])/60.0 + float(parts[2])/3600.0
    except:
        return -1.0

def parse_dms(s):
    try:
        ss = str(s).replace(':', ' ').strip()
        sign = -1 if ss.startswith('-') else 1
        parts = ss.replace('-', '').split()
        return sign * (float(parts[0]) + float(parts[1])/60.0 + float(parts[2])/3600.0)
    except:
        return -999.0

def angular_separation_deg(ra1_h, dec1_deg, ra2_h, dec2_deg):
    ra1 = math.radians(ra1_h * 15.0)
    dec1 = math.radians(dec1_deg)
    ra2 = math.radians(ra2_h * 15.0)
    dec2 = math.radians(dec2_deg)
    cos_sep = (math.sin(dec1) * math.sin(dec2) +
               math.cos(dec1) * math.cos(dec2) * math.cos(ra1 - ra2))
    cos_sep = max(-1.0, min(1.0, cos_sep))
    return math.degrees(math.acos(cos_sep))


def verify_wide_field_dark_nebula_survey(traj, env_info, task_info):
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
    valid_fits = [f for f in fits_files 
                  if f.get('mtime', 0) > task_start and f.get('size', 0) > 2048]

    # --- Criteria 1-3: FITS Frames per Target ---
    def evaluate_target(target_name):
        frames = [f for f in valid_fits if f.get('dir') == target_name]
        valid_pointing_frames = 0
        
        target_coords = TARGETS[target_name]
        
        for f in frames:
            # Verify coordinates are somewhat close
            ra_h = parse_hms(f.get('objra', ''))
            dec_d = parse_dms(f.get('objdec', ''))
            
            if ra_h >= 0 and dec_d > -900:
                sep = angular_separation_deg(ra_h, dec_d, target_coords['ra'], target_coords['dec'])
                if sep <= COORD_TOL_DEG:
                    valid_pointing_frames += 1

        if valid_pointing_frames >= 2:
            return 15, f"{target_name}: {valid_pointing_frames} frames correctly positioned"
        elif valid_pointing_frames == 1:
            return 7, f"{target_name}: 1 frame correctly positioned"
        elif len(frames) > 0:
            return 0, f"{target_name}: {len(frames)} frames found, but telescope was not pointed at the correct coordinates"
        else:
            return 0, f"{target_name}: no valid frames found"

    for target in ['B33', 'B143', 'B86']:
        pts, msg = evaluate_target(target)
        score += pts
        feedback.append(msg)

    # --- Criterion 4: Equipment Reconfiguration (25 pts) ---
    if len(valid_fits) > 0:
        correct_config = 0
        for f in valid_fits:
            if abs(f.get('focallen', 0) - 135.0) < 1.0 and abs(f.get('aptdia', 0) - 50.0) < 1.0:
                correct_config += 1
                
        if correct_config == len(valid_fits):
            score += 25
            feedback.append("Equipment optics reconfigured correctly for all frames (135mm FL / 50mm Apt)")
        elif correct_config > 0:
            score += 12
            feedback.append(f"Equipment reconfigured for {correct_config}/{len(valid_fits)} frames")
        else:
            feedback.append("Equipment was NOT reconfigured (FITS headers show narrow field optics)")
    else:
        feedback.append("No valid frames to check equipment reconfiguration")

    # --- Criterion 5: Contextual Sky Views (15 pts) ---
    sky_views = result.get('sky_views', {})
    sky_count = sum(1 for v in sky_views.values() if v)
    if sky_count == 3:
        score += 15
        feedback.append("Sky views successfully created for all 3 targets")
    elif sky_count > 0:
        score += 5 * sky_count
        feedback.append(f"Sky views created for {sky_count}/3 targets")
    else:
        feedback.append("No sky views created")

    # --- Criterion 6: Survey Log (15 pts) ---
    log_exists = result.get('log_exists', False)
    if log_exists:
        log_text = base64.b64decode(result.get('log_b64', '')).decode('utf-8', errors='ignore').lower()
        if '135' in log_text and ('b33' in log_text or 'horsehead' in log_text or 'b143' in log_text or 'b86' in log_text):
            score += 15
            feedback.append("Survey log created and content looks correct")
        else:
            score += 5
            feedback.append("Survey log exists but missing expected target details or 135mm confirmation")
    else:
        feedback.append("Survey log not found")

    # --- Final Assessment ---
    # Agent must get at least 60 points, which requires configuring equipment AND actually observing some targets
    passed = score >= 60

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }