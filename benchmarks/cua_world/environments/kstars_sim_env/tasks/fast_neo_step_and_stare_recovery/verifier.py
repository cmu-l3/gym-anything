#!/usr/bin/env python3
"""
Verifier for fast_neo_step_and_stare_recovery task.

Occupation: Planetary Scientist
Context: Step-and-stare observation sequence for a fast NEO + Animation generation

Criteria (100 pts total, pass >= 65):
1. FITS files generated in tracking directory (>=5)               - 10 pts
2. WP1 captured accurately (within 0.15 deg)                      - 11 pts
3. WP2 captured accurately (within 0.15 deg)                      - 11 pts
4. WP3 captured accurately (within 0.15 deg)                      - 11 pts
5. WP4 captured accurately (within 0.15 deg)                      - 11 pts
6. WP5 captured accurately (within 0.15 deg)                      - 11 pts
7. Correct filter used (Luminance/Slot 1)                         - 10 pts
8. GIF creation: exists, >10KB, >=4 frames, loops, ~500ms dur.    - 25 pts
"""

import json
import os
import math
import re
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

WAYPOINTS = [
    {"ra": 9.7500, "dec": 20.2500},
    {"ra": 9.7833, "dec": 19.8333},
    {"ra": 9.8167, "dec": 19.4167},
    {"ra": 9.8500, "dec": 19.0000},
    {"ra": 9.8833, "dec": 18.5833}
]
COORD_TOL_DEG = 0.15


def angular_separation_deg(ra1_h, dec1_deg, ra2_h, dec2_deg):
    ra1 = math.radians(ra1_h * 15.0)
    dec1 = math.radians(dec1_deg)
    ra2 = math.radians(ra2_h * 15.0)
    dec2 = math.radians(dec2_deg)
    cos_sep = (math.sin(dec1) * math.sin(dec2) +
               math.cos(dec1) * math.cos(dec2) * math.cos(ra1 - ra2))
    cos_sep = max(-1.0, min(1.0, cos_sep))
    return math.degrees(math.acos(cos_sep))


def parse_coord(val, is_ra=True):
    """Robust parser for FITS coordinate strings (hours/degrees)."""
    if isinstance(val, (float, int)):
        if is_ra and val > 24.0:
            return float(val) / 15.0
        return float(val)
    
    val_str = str(val).strip()
    if not val_str:
        return -999.0
        
    parts = re.split(r'[:\s]+', val_str)
    if len(parts) >= 3:
        try:
            sign = -1.0 if parts[0].startswith('-') else 1.0
            d = abs(float(parts[0]))
            m = float(parts[1])
            s = float(parts[2])
            return sign * (d + m/60.0 + s/3600.0)
        except ValueError:
            return -999.0
    try:
        f = float(val_str)
        if is_ra and f > 24.0:
            return f / 15.0
        return f
    except ValueError:
        return -999.0


def verify_fast_neo_step_and_stare(traj, env_info, task_info):
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
    
    # Anti-gaming: Ensure files were created during this session
    all_fits = result.get('fits_files', [])
    valid_fits = [f for f in all_fits if f.get('mtime', 0) > task_start and f.get('size', 0) > 2048]
    valid_count = len(valid_fits)

    # 1. Check File Generation (10 pts)
    if valid_count >= 5:
        score += 10
        feedback.append(f"Captured {valid_count} FITS images (>=5 required).")
    elif valid_count > 0:
        score += 5
        feedback.append(f"Captured only {valid_count}/5 FITS images.")
    else:
        feedback.append("No valid FITS images captured in the target directory.")

    # 2-6. Check Waypoints (11 pts each)
    waypoints_hit = 0
    for i, wp in enumerate(WAYPOINTS):
        matched = False
        min_sep = 999.0
        for f in valid_fits:
            ra = parse_coord(f.get('ra', -999.0), is_ra=True)
            dec = parse_coord(f.get('dec', -999.0), is_ra=False)
            
            if ra != -999.0 and dec != -999.0:
                sep = angular_separation_deg(ra, dec, wp['ra'], wp['dec'])
                if sep < min_sep:
                    min_sep = sep
                if sep <= COORD_TOL_DEG:
                    matched = True
                    break
                    
        if matched:
            score += 11
            waypoints_hit += 1
            feedback.append(f"Waypoint {i+1} captured successfully.")
        else:
            if min_sep < 999.0:
                feedback.append(f"Waypoint {i+1} missed (closest capture was {min_sep:.2f} deg away).")
            else:
                feedback.append(f"Waypoint {i+1} missed (no valid FITS coordinates to check).")

    # 7. Check Filter (10 pts)
    # Give points if at least one file proves Luminance/Clear or default Slot 1 was used
    filter_ok = False
    for f in valid_fits:
        filt_str = f.get('filter', '').upper()
        if filt_str in ('L', 'LUM', 'LUMINANCE', 'CLEAR', '1', ''):
            filter_ok = True
            break
            
    if filter_ok and valid_count > 0:
        score += 10
        feedback.append("Luminance/Clear filter verified.")
    elif valid_count > 0:
        feedback.append("Incorrect filter used.")

    # 8. Check GIF Creation (25 pts)
    gif_info = result.get('gif', {})
    gif_exists = gif_info.get('exists', False)
    gif_mtime = gif_info.get('mtime', 0)
    gif_size = gif_info.get('size', 0)
    gif_frames = gif_info.get('frames', 0)
    gif_duration = gif_info.get('duration', 0)
    gif_loop = gif_info.get('loop', -1)
    
    if gif_exists and gif_mtime > task_start and gif_size > 10240:
        score += 10
        feedback.append(f"Valid GIF created ({gif_size/1024:.1f} KB).")
        
        # Frame check
        if gif_frames >= 4:
            score += 5
            feedback.append(f"GIF contains {gif_frames} frames.")
        else:
            feedback.append(f"GIF has only {gif_frames} frames (need >= 4).")
            
        # Duration check (~500ms)
        if 400 <= gif_duration <= 600:
            score += 5
            feedback.append(f"GIF frame duration verified ({gif_duration}ms).")
        else:
            feedback.append(f"GIF duration is {gif_duration}ms (expected ~500ms).")
            
        # Loop check
        if gif_loop == 0:
            score += 5
            feedback.append("GIF set to loop infinitely.")
        else:
            feedback.append("GIF is not set to loop infinitely.")
    else:
        feedback.append("Animated GIF not successfully created or too small.")

    # Pass threshold: 65 points (Ensures most waypoints + scripting attempt)
    passed = score >= 65 and waypoints_hit >= 3
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }