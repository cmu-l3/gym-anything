#!/usr/bin/env python3
import json
import base64
import os
import math
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def angular_separation_deg(ra1_h, dec1_deg, ra2_h, dec2_deg):
    """Calculates true sky distance between two equatorial coordinates."""
    ra1 = math.radians(ra1_h * 15.0)
    dec1 = math.radians(dec1_deg)
    ra2 = math.radians(ra2_h * 15.0)
    dec2 = math.radians(dec2_deg)
    cos_sep = (math.sin(dec1) * math.sin(dec2) +
               math.cos(dec1) * math.cos(dec2) * math.cos(ra1 - ra2))
    cos_sep = max(-1.0, min(1.0, cos_sep))
    return math.degrees(math.acos(cos_sep))

def verify_high_z_quasar_survey(traj, env_info, task_info):
    """
    Verification strategy:
    1. Assess each target's FITS files independently.
       Requires L and R frames saved to matching paths AND embedded header coordinates. (60 pts max)
    2. Assess DSS2 reference tiles.
       Ensures images were retrieved accurately for each target area. (25 pts max)
    3. Assess the completion log.
       Must mention targets observed. (15 pts max)
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System error: copy_from_env unavailable"}

    metadata = task_info.get('metadata', {})
    targets = metadata.get('targets', [
      {"name": "3C273", "ra": 12.485, "dec": 2.052, "tol": 0.5},
      {"name": "TON618", "ra": 12.474, "dec": 35.967, "tol": 0.5},
      {"name": "PG1634", "ra": 16.575, "dec": 70.526, "tol": 0.5}
    ])

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
    log_exists = result.get('log_exists', False)
    log_mtime = result.get('log_mtime', 0)
    log_b64 = result.get('log_b64', '')

    # Enforce anti-gaming: ignore decoy files and filter by minimum practical size
    valid_fits = [f for f in fits_files if f.get('mtime', 0) > task_start and f.get('size', 0) > 2048]
    valid_pngs = [f for f in png_files if f.get('mtime', 0) > task_start and f.get('size', 0) > 1024]

    def evaluate_target(tname, expected_ra, expected_dec, tol):
        """Find matching FITS entries organized correctly in target's directory tree."""
        target_fits = [f for f in valid_fits if f.get('path', '').upper().find(f"QUASARS/{tname.upper()}") != -1]
        
        # Look for L and R frames
        l_frames = [f for f in target_fits if '/L/' in f.get('path', '').upper()]
        r_frames = [f for f in target_fits if '/R/' in f.get('path', '').upper()]

        # Filter by those actually taken while pointed at the object
        l_valid = [f for f in l_frames if angular_separation_deg(f.get('ra', -1), f.get('dec', -999), expected_ra, expected_dec) <= tol]
        r_valid = [f for f in r_frames if angular_separation_deg(f.get('ra', -1), f.get('dec', -999), expected_ra, expected_dec) <= tol]

        pts = 0
        if len(l_valid) >= 3 and len(r_valid) >= 3:
            pts = 20
        elif len(l_valid) >= 1 and len(r_valid) >= 1:
            pts = 10
        elif len(l_valid) >= 1 or len(r_valid) >= 1:
            pts = 5
        return pts, len(l_valid), len(r_valid)

    # 1. Evaluate Quasar Targets
    for tgt in targets:
        pts, lc, rc = evaluate_target(tgt['name'], tgt['ra'], tgt['dec'], tgt['tol'])
        score += pts
        if pts == 20:
            feedback.append(f"{tgt['name']} fully acquired ({lc} L, {rc} R frames)")
        elif pts > 0:
            feedback.append(f"{tgt['name']} partially acquired ({lc} L, {rc} R frames)")
        else:
            feedback.append(f"{tgt['name']} not properly acquired")

    # 2. Evaluate PNG reference downloads
    png_count = 0
    for tgt in targets:
        if any(f.get('path', '').upper().find(f"QUASARS/{tgt['name'].upper()}") != -1 for f in valid_pngs):
            png_count += 1
            
    if png_count == 3:
        score += 25
        feedback.append("All 3 DSS2 reference images successfully captured")
    elif png_count > 0:
        score += png_count * 8
        feedback.append(f"{png_count}/3 DSS2 reference images captured")
    else:
        feedback.append("No valid DSS2 reference images found")

    # 3. Evaluate Logging
    if log_exists and log_mtime > task_start:
        try:
            log_text = base64.b64decode(log_b64).decode('utf-8', errors='ignore').upper()
            found_targets = 0
            for tgt in targets:
                syn1 = tgt['name'].upper()
                syn2 = syn1.replace("3C273", "3C 273").replace("TON618", "TON 618").replace("PG1634", "PG 1634")
                if syn1 in log_text or syn2 in log_text:
                    found_targets += 1
            
            if found_targets >= 2:
                score += 15
                feedback.append(f"Survey log created referencing {found_targets} targets")
            elif found_targets == 1:
                score += 7
                feedback.append(f"Survey log created but only references {found_targets} target")
            else:
                score += 5
                feedback.append("Survey log created but missing recognized target designations")
        except Exception as e:
            score += 5
            feedback.append("Survey log created but could not be parsed fully")
    else:
        feedback.append("Survey log not created or predates task")

    passed = score >= 65
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }