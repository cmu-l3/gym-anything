#!/usr/bin/env python3
"""
Verifier for xray_optical_counterpart_search task.

Occupation: Astronomer / Observational Astrophysicist
Context: X-ray binary optical follow-up (Cygnus X-1, Scorpius X-1, V404 Cygni)

Criteria (100 pts total, pass >= 70):
1. Cyg X-1 data (≥5 B-band and ≥5 V-band FITS)              - 20 pts
2. Sco X-1 data (≥5 B-band and ≥5 V-band FITS)              - 20 pts
3. V404 Cyg data (≥5 B-band and ≥5 V-band FITS)             - 20 pts
4. Reference sky maps (cool palette PNGs for all targets)   - 15 pts
5. Directory isolation (files organized in subdirectories)  - 15 pts
6. Summary report created                                   - 10 pts
"""

import json
import base64
import os
import math
import tempfile
import logging
import re

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

TARGETS = {
    'cygx1': {'ra': 19.972, 'dec': 35.201, 'dir_keyword': 'cygx1'},
    'scox1': {'ra': 16.332, 'dec': -15.640, 'dir_keyword': 'scox1'},
    'v404cyg': {'ra': 20.401, 'dec': 33.867, 'dir_keyword': 'v404'}
}

def parse_coord(coord_str):
    if not coord_str:
        return None
    nums = re.findall(r'[-+]?\d*\.\d+|\d+', str(coord_str))
    if len(nums) >= 3:
        sign = -1 if '-' in coord_str else 1
        d = abs(float(nums[0]))
        return sign * (d + float(nums[1])/60.0 + float(nums[2])/3600.0)
    elif len(nums) == 1:
        return float(nums[0])
    return None

def angular_separation_deg(ra1_h, dec1_deg, ra2_h, dec2_deg):
    ra1 = math.radians(ra1_h * 15.0)
    dec1 = math.radians(dec1_deg)
    ra2 = math.radians(ra2_h * 15.0)
    dec2 = math.radians(dec2_deg)
    cos_sep = (math.sin(dec1) * math.sin(dec2) +
               math.cos(dec1) * math.cos(dec2) * math.cos(ra1 - ra2))
    cos_sep = max(-1.0, min(1.0, cos_sep))
    return math.degrees(math.acos(cos_sep))

def get_target_for_file(f, is_png=False):
    # If it's a FITS file, try matching by coordinates first
    if not is_png:
        ra = parse_coord(f.get('ra_str', ''))
        dec = parse_coord(f.get('dec_str', ''))
        
        if ra is not None and dec is not None:
            for t_name, t_info in TARGETS.items():
                # FITS RA might be in hours or degrees
                ra_h = ra if ra < 24 else ra / 15.0
                sep = angular_separation_deg(ra_h, dec, t_info['ra'], t_info['dec'])
                if sep <= 1.0:
                    return t_name
                    
    # Fallback to directory name matching
    dname = str(f.get('dir', '')).lower()
    for t_name, t_info in TARGETS.items():
        if t_info['dir_keyword'] in dname:
            return t_name
            
    return None

def verify_xray_optical_counterpart_search(traj, env_info, task_info):
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

    task_start = result.get('task_start', 0)
    fits_files = result.get('fits_files', [])
    png_files = result.get('png_files', [])
    
    valid_fits = [f for f in fits_files if f.get('mtime', 0) > task_start and f.get('size', 0) > 2048]
    valid_pngs = [p for p in png_files if p.get('mtime', 0) > task_start and p.get('size', 0) > 1024]
    
    score = 0
    feedback = []
    
    dirs_used = set()
    png_targets_found = set()
    
    # ── Check individual targets (20 pts each) ──────────────────────────
    for t_name in TARGETS.keys():
        t_fits = [f for f in valid_fits if get_target_for_file(f, is_png=False) == t_name]
        b_count = sum(1 for f in t_fits if 'B' in f.get('filter', '').upper())
        v_count = sum(1 for f in t_fits if 'V' in f.get('filter', '').upper())
        
        for f in t_fits:
            dirs_used.add(f.get('dir', ''))
            
        t_pngs = [p for p in valid_pngs if get_target_for_file(p, is_png=True) == t_name]
        if t_pngs:
            png_targets_found.add(t_name)
            
        if b_count >= 5 and v_count >= 5:
            score += 20
            feedback.append(f"{t_name}: {b_count} B-band, {v_count} V-band frames")
        elif b_count >= 3 and v_count >= 3:
            score += 10
            feedback.append(f"{t_name}: {b_count}/5 B-band, {v_count}/5 V-band")
        elif b_count >= 1 or v_count >= 1:
            score += 5
            feedback.append(f"{t_name}: Incomplete frames ({b_count} B, {v_count} V)")
        else:
            feedback.append(f"{t_name}: No valid FITS frames found")
            
    # ── Check Reference Sky Maps (15 pts) ───────────────────────────────
    png_count = len(png_targets_found)
    if png_count >= 3:
        score += 15
        feedback.append("All 3 reference sky maps generated")
    elif png_count == 2:
        score += 10
        feedback.append("2/3 reference sky maps generated")
    elif png_count == 1:
        score += 5
        feedback.append("1/3 reference sky maps generated")
    else:
        feedback.append("No reference sky maps generated")
        
    # ── Check Directory Isolation (15 pts) ──────────────────────────────
    dirs_clean = {d for d in dirs_used if d and d != 'xray_followup'}
    if len(dirs_clean) >= 3:
        score += 15
        feedback.append("Data correctly isolated in 3+ subdirectories")
    elif len(dirs_clean) == 2:
        score += 10
        feedback.append("Data partially isolated (2 subdirectories used)")
    elif len(dirs_clean) == 1:
        score += 5
        feedback.append("All data saved to a single subdirectory")
    else:
        feedback.append("Data not organized into subdirectories")
        
    # ── Check Summary Report (10 pts) ───────────────────────────────────
    report_exists = result.get('report_exists', False)
    report_mtime = result.get('report_mtime', 0)
    
    if report_exists and report_mtime > task_start:
        score += 10
        feedback.append("Summary report created during task")
    elif report_exists:
        score += 2
        feedback.append("Summary report exists but not updated")
    else:
        feedback.append("Summary report not found")
        
    passed = score >= 70
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }