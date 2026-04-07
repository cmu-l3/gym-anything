#!/usr/bin/env python3
"""
Verifier for hubble_sequence_rgb_survey task.

Occupation: Observational Astronomer / Extragalactic Survey Researcher
Context: Observing 4 galaxies of different Hubble types in RGB to build an atlas.

Criteria (100 pts total, pass >= 60):
1. M87 FITS frames (R,V,B, >=2 each)      - 12 pts (4 per filter)
2. M104 FITS frames (R,V,B, >=2 each)     - 12 pts (4 per filter)
3. M51 FITS frames (R,V,B, >=2 each)      - 12 pts (4 per filter)
4. NGC4449 FITS frames (R,V,B, >=2 each)  - 12 pts (4 per filter)
5. Directory structure (all 12 exist)     - 8 pts
6. Telescope near any target              - 10 pts
7. False-color composites (4 files >50KB) - 16 pts (4 each)
8. Sky view captures (>=2 PNGs)           - 8 pts
9. Survey catalog exists                  - 5 pts
10. Catalog content valid                 - 5 pts

Anti-gaming:
- M87/R contains stale pre-task files which must be ignored based on mtime.
- Only new, valid-sized (>2KB for FITS, >50KB for composites) files count.
- Final position must be close to at least one of the targets (agent actually slewed).
"""

import json
import base64
import os
import math
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def angular_separation_deg(ra1_h, dec1_deg, ra2_h, dec2_deg):
    ra1 = math.radians(ra1_h * 15.0)
    dec1 = math.radians(dec1_deg)
    ra2 = math.radians(ra2_h * 15.0)
    dec2 = math.radians(dec2_deg)
    cos_sep = (math.sin(dec1) * math.sin(dec2) +
               math.cos(dec1) * math.cos(dec2) * math.cos(ra1 - ra2))
    cos_sep = max(-1.0, min(1.0, cos_sep))
    return math.degrees(math.acos(cos_sep))

def verify_hubble_sequence_rgb_survey(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System error: copy_from_env unavailable"}

    metadata = task_info.get('metadata', {})
    targets = metadata.get('targets', {
        "M87": {"ra": 12.5136, "dec": 12.3911},
        "M104": {"ra": 12.6664, "dec": -11.6231},
        "M51": {"ra": 13.4981, "dec": 47.1953},
        "NGC4449": {"ra": 12.4697, "dec": 44.0944}
    })
    coord_tol_deg = metadata.get('coordinate_tolerance_deg', 2.0)
    req_frames = metadata.get('required_frames_per_filter', 2)

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
    files_info = result.get('files_info', [])

    # Filter for active files
    valid_files = [f for f in files_info if f.get('mtime', 0) > task_start]

    # --- Criteria 1-5: FITS & Directories ---
    # We will score each object. For each object, we check R, V, B.
    # Total points per object = 12 (4 pts per filter where count >= 2)
    # We also track directory existence.
    objects = ["M87", "M104", "M51", "NGC4449"]
    filters = ["R", "V", "B"]
    dirs_found = set()

    for obj in objects:
        obj_pts = 0
        counts = {}
        for filt in filters:
            # Look for files like <obj>/<filt>/*.fits or filter header match
            expected_dir_part = f"{obj.lower()}/{filt.lower()}/"
            count = 0
            for f in valid_files:
                name = f.get('name', '').lower()
                rel = f.get('rel_path', '').lower()
                size = f.get('size', 0)
                if size < 2048 or not (name.endswith('.fits') or name.endswith('.fit')):
                    continue
                # If it's in the exact subfolder or has the right name prefix
                if expected_dir_part in rel or (f"{obj.lower()}/" in rel and filt.lower() in f.get('filter', '').lower()):
                    count += 1
                    dirs_found.add(f"{obj}/{filt}")
            
            counts[filt] = count
            if count >= req_frames:
                obj_pts += 4
            elif count >= 1:
                obj_pts += 2
                
        score += obj_pts
        if obj_pts == 12:
            feedback.append(f"{obj} FITS: complete (12/12 pts)")
        elif obj_pts > 0:
            feedback.append(f"{obj} FITS: partial ({counts}) ({obj_pts}/12 pts)")
        else:
            feedback.append(f"{obj} FITS: missing")

    # Directory Structure (8 pts)
    # 12 expected (4 objects x 3 filters)
    dir_ratio = len(dirs_found) / 12.0
    dir_pts = int(8 * dir_ratio)
    score += dir_pts
    if dir_pts > 0:
        feedback.append(f"Directory structure: {len(dirs_found)}/12 found ({dir_pts}/8 pts)")

    # --- Criterion 6: Telescope Position ---
    try:
        final_ra = float(result.get('final_ra', -1))
        final_dec = float(result.get('final_dec', -999))
    except (ValueError, TypeError):
        final_ra, final_dec = -1.0, -999.0

    pos_ok = False
    if final_ra > 0 and final_dec > -900:
        min_sep = 999.0
        nearest_target = ""
        for name, coords in targets.items():
            sep = angular_separation_deg(final_ra, final_dec, coords['ra'], coords['dec'])
            if sep < min_sep:
                min_sep = sep
                nearest_target = name
        
        if min_sep <= coord_tol_deg:
            score += 10
            pos_ok = True
            feedback.append(f"Telescope near {nearest_target} (sep {min_sep:.1f}°)")
        else:
            feedback.append(f"Telescope not near any target (nearest {nearest_target} at {min_sep:.1f}°)")
    else:
        feedback.append("Could not read telescope coordinates")

    # --- Criterion 7: False-color composites (16 pts) ---
    composite_pts = 0
    composites_found = 0
    for obj in objects:
        for f in valid_files:
            rel = f.get('rel_path', '').lower()
            size = f.get('size', 0)
            if size > 50000 and "composite" in rel and ".png" in rel and obj.lower() in rel:
                composites_found += 1
                composite_pts += 4
                break
    score += composite_pts
    if composites_found > 0:
        feedback.append(f"Composites: {composites_found}/4 found ({composite_pts}/16 pts)")
    else:
        feedback.append("Composites: missing")

    # --- Criterion 8: Sky View Captures (8 pts) ---
    sky_caps = 0
    for f in valid_files:
        rel = f.get('rel_path', '').lower()
        if "sky" in rel and ".png" in rel and "composite" not in rel:
            sky_caps += 1
            
    if sky_caps >= 2:
        score += 8
        feedback.append(f"Sky captures: {sky_caps} found (8/8 pts)")
    elif sky_caps == 1:
        score += 4
        feedback.append("Sky captures: 1 found (4/8 pts)")
    else:
        feedback.append("Sky captures: missing")

    # --- Criteria 9 & 10: Survey Catalog (10 pts) ---
    cat_exists = result.get('catalog_exists', False)
    cat_mtime = result.get('catalog_mtime', 0)
    
    if cat_exists and cat_mtime > task_start:
        score += 5
        feedback.append("Catalog file exists")
        
        cat_b64 = result.get('catalog_b64', '')
        if cat_b64:
            try:
                cat_text = base64.b64decode(cat_b64).decode('utf-8', errors='ignore').upper()
                obj_matches = sum(1 for obj in objects if obj.upper() in cat_text)
                type_matches = sum(1 for t in ["E0", "SA", "SC", "IBM", "ELLIPTICAL", "SPIRAL", "IRREGULAR"] if t in cat_text)
                
                if obj_matches >= 3 and type_matches >= 2:
                    score += 5
                    feedback.append("Catalog content valid")
                elif obj_matches > 0:
                    score += 2
                    feedback.append("Catalog content partially valid")
                else:
                    feedback.append("Catalog missing target designations")
            except:
                feedback.append("Could not decode catalog content")
    else:
        feedback.append("Catalog file missing or pre-dates task")

    passed = score >= 60

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }