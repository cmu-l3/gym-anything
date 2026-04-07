#!/usr/bin/env python3
"""
Verifier for galaxy_cluster_lensing_atlas task.

Criteria (100 pts total, pass >= 65):
1. Abell 1689: Valid FITS (15 pts) + Reference PNG (5 pts) = 20 pts
2. Abell 2218: Valid FITS (22 pts) + Reference PNG (8 pts) = 30 pts 
   (High value reflects coordinate conversion trap: 248.975 deg -> 16.598 hours)
3. Abell 370: Valid FITS (15 pts) + Reference PNG (5 pts) = 20 pts
4. Image Parameters: PNG sizes indicate actual successful renderings (5 pts per valid PNG) = 15 pts
5. Observation Log: Exists, fresh, and contains cluster names = 15 pts
"""

import json
import os
import math
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def angular_separation_deg(ra1_deg, dec1_deg, ra2_deg, dec2_deg):
    ra1 = math.radians(ra1_deg)
    dec1 = math.radians(dec1_deg)
    ra2 = math.radians(ra2_deg)
    dec2 = math.radians(dec2_deg)
    cos_sep = (math.sin(dec1) * math.sin(dec2) +
               math.cos(dec1) * math.cos(dec2) * math.cos(ra1 - ra2))
    cos_sep = max(-1.0, min(1.0, cos_sep))
    return math.degrees(math.acos(cos_sep))

def verify_galaxy_cluster_lensing_atlas(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System error: copy_from_env unavailable"}

    metadata = task_info.get('metadata', {})
    targets = metadata.get('targets', {})
    tol_deg = metadata.get('tolerance_deg', 0.25)
    req_exptime = metadata.get('required_exptime', 60)
    
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
    png_files = result.get('png_files', [])
    
    def evaluate_target(target_id, fits_pts, png_pts):
        t_data = targets.get(target_id)
        if not t_data: return 0
        
        expected_ra_deg = t_data['ra_hours'] * 15.0
        expected_dec_deg = t_data['dec_deg']
        
        target_score = 0
        
        # 1. Check FITS
        fits_ok = False
        for f in fits_files:
            # Must be fresh and in correct directory (case insensitive)
            if f.get('mtime', 0) > task_start and f.get('dir', '').upper() == target_id.upper():
                # Check exposure time (allow small deviations)
                if abs(f.get('exptime', 0) - req_exptime) > 2.0:
                    continue
                # Check filter (Luminance or slot 1)
                filt = f.get('filter', '').upper()
                if filt not in ('1', 'L', 'LUM', 'LUMINANCE'):
                    continue
                # Check coordinates
                ra = f.get('obj_ra_deg', -999)
                dec = f.get('obj_dec_deg', -999)
                if ra > -900 and dec > -900:
                    sep = angular_separation_deg(ra, dec, expected_ra_deg, expected_dec_deg)
                    if sep <= tol_deg:
                        fits_ok = True
                        break
        if fits_ok:
            target_score += fits_pts
            feedback.append(f"{target_id}: Valid FITS found (+{fits_pts})")
        else:
            feedback.append(f"{target_id}: No valid FITS found")

        # 2. Check PNG
        png_ok = False
        for p in png_files:
            if p.get('mtime', 0) > task_start and p.get('dir', '').upper() == target_id.upper():
                if 'reference.png' in p.get('name', '').lower():
                    png_ok = True
                    break
        if png_ok:
            target_score += png_pts
            feedback.append(f"{target_id}: Fresh reference.png found (+{png_pts})")
        else:
            feedback.append(f"{target_id}: No fresh reference.png found")
            
        return target_score

    # Evaluate each target
    score += evaluate_target('Abell1689', fits_pts=15, png_pts=5)
    score += evaluate_target('Abell2218', fits_pts=22, png_pts=8)
    score += evaluate_target('Abell370', fits_pts=15, png_pts=5)

    # Evaluate Image Parameters (file sizes of PNGs indicate rendering succeeded)
    png_size_score = 0
    for target_id in targets.keys():
        for p in png_files:
            if p.get('mtime', 0) > task_start and p.get('dir', '').upper() == target_id.upper() and p.get('size', 0) > 20000:
                png_size_score += 5
                break
    score += png_size_score
    if png_size_score > 0:
        feedback.append(f"Image Params: High-res renders verified (+{png_size_score})")

    # Evaluate Observation Log
    if result.get('log_exists') and result.get('log_mtime', 0) > task_start:
        log_content = result.get('log_content', '').upper()
        mentions = sum(1 for tid in ['1689', '2218', '370'] if tid in log_content)
        if mentions == 3:
            score += 15
            feedback.append("Log: Valid observation log generated (+15)")
        elif mentions > 0:
            score += 5
            feedback.append(f"Log: Incomplete log found ({mentions}/3 clusters) (+5)")
        else:
            feedback.append("Log: Log file exists but lacks required cluster IDs")
    else:
        feedback.append("Log: No valid atlas_log.txt found")

    passed = score >= 65
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }