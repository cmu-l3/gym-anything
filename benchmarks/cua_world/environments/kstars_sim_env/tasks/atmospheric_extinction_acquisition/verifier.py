#!/usr/bin/env python3
"""
Verifier for atmospheric_extinction_acquisition task.

Occupation: Observatory Calibration Scientist
Context: Acquiring V-band exposures of standard stars to compute the nightly extinction curve.

Criteria (100 pts total, pass >= 70):
1. Extinction Directories: 4 distinct subdirectories created        (10 pts)
2. Image Counts: >=3 valid FITS per directory                       (20 pts)
3. Instrument Config: FITS are V-band and 5s exposure               (15 pts)
4. Distinct Targets: FITS coordinates cluster into 4 separate stars (20 pts)
5. Altitude Constraint: The observed stars were > 20 deg Alt        (20 pts)
6. Scientific Report: Valid Airmass math found in report            (15 pts)

Anti-gaming protections:
- Altitude is calculated mathematically from RA/Dec and the exact UNIX timestamp (mtime) 
  of the FITS creation, using Astropy during export. 
- FITS mtime > task_start guarantees fresh data.
- Math validation checks relationships between raw extracted numbers, preventing formatting brittleness.
"""

import json
import base64
import os
import math
import re
import tempfile
import logging
from collections import defaultdict

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def angular_separation_deg(ra1_deg, dec1_deg, ra2_deg, dec2_deg):
    """Calculate great circle separation between two points."""
    ra1 = math.radians(ra1_deg)
    dec1 = math.radians(dec1_deg)
    ra2 = math.radians(ra2_deg)
    dec2 = math.radians(dec2_deg)
    cos_sep = (math.sin(dec1) * math.sin(dec2) +
               math.cos(dec1) * math.cos(dec2) * math.cos(ra1 - ra2))
    cos_sep = max(-1.0, min(1.0, cos_sep))
    return math.degrees(math.acos(cos_sep))


def get_distinct_targets(valid_fits):
    """Cluster FITS into distinct targets (separated by >2 degrees)."""
    targets = []
    for f in valid_fits:
        ra = f.get('ra_deg', -999)
        dec = f.get('dec_deg', -999)
        alt = f.get('alt_deg', -999)
        if ra == -999 or dec == -999:
            continue
        
        is_new = True
        for i, (t_ra, t_dec, alts, count) in enumerate(targets):
            sep = angular_separation_deg(ra, dec, t_ra, t_dec)
            if sep < 2.0:
                targets[i][2].append(alt)
                targets[i][3] += 1
                is_new = False
                break
                
        if is_new:
            targets.append([ra, dec, [alt], 1])
            
    return targets


def check_report_math(report_text):
    """Find pairs of numbers (Altitude, Airmass) where Airmass = 1/sin(Altitude)."""
    # Extract all floats/ints from text
    nums = [float(x) for x in re.findall(r"[-+]?(?:\d*\.\d+|\d+)", report_text)]
    valid_pairs = 0
    used = set()
    
    for i, a in enumerate(nums):
        if i in used:
            continue
        # If this number could be an altitude in degrees
        if 20.0 <= a <= 90.0:
            expected = 1.0 / math.sin(math.radians(a))
            # Scan for its airmass counterpart
            for j, x in enumerate(nums):
                if j == i or j in used:
                    continue
                if abs(x - expected) < 0.1:  # allow rounding margin
                    valid_pairs += 1
                    used.add(i)
                    used.add(j)
                    break
                    
    return valid_pairs


def verify_atmospheric_extinction_acquisition(traj, env_info, task_info):
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
    
    # ── 1. Directories & Image Counts ─────────────────────────────────
    dir_counts = defaultdict(int)
    for f in valid_fits:
        d = f.get('dir', '')
        if d and d != 'extinction':
            dir_counts[d] += 1
            
    valid_dirs = len(dir_counts.keys())
    score += min(10, int((valid_dirs / 4.0) * 10))
    feedback.append(f"Found {valid_dirs} target directories")
    
    dirs_with_enough_images = sum(1 for d, c in dir_counts.items() if c >= 3)
    score += min(20, int((dirs_with_enough_images / 4.0) * 20))
    feedback.append(f"Found {dirs_with_enough_images} dirs with >=3 frames")
    
    # ── 2. Instrument Configuration ───────────────────────────────────
    correct_config_count = 0
    for f in valid_fits:
        filt = str(f.get('filter', '')).upper()
        exptime = f.get('exptime', -1)
        if ('V' in filt or '2' in filt) and abs(exptime - 5.0) < 0.5:
            correct_config_count += 1
            
    if len(valid_fits) > 0:
        config_ratio = correct_config_count / len(valid_fits)
        if config_ratio >= 0.9:
            score += 15
            feedback.append("Filter (V) and Exptime (5s) configured correctly")
        elif config_ratio >= 0.5:
            score += 7
            feedback.append("Filter/Exptime partially correct")
        else:
            feedback.append("Incorrect Filter/Exptime on most frames")
    else:
        feedback.append("No valid frames to check config")
        
    # ── 3. Distinct Targets & Altitude Constraint ─────────────────────
    targets = get_distinct_targets(valid_fits)
    num_distinct = len(targets)
    score += min(20, int((num_distinct / 4.0) * 20))
    feedback.append(f"Observed {num_distinct} distinct star(s)")
    
    targets_above_horizon = 0
    for ra, dec, alts, count in targets:
        # Calculate average altitude for this target's frames
        valid_alts = [a for a in alts if a != -999]
        if valid_alts:
            avg_alt = sum(valid_alts) / len(valid_alts)
            if avg_alt > 20.0:
                targets_above_horizon += 1

    score += min(20, int((targets_above_horizon / 4.0) * 20))
    feedback.append(f"Targets meeting Altitude > 20 deg rule: {targets_above_horizon}")

    # ── 4. Scientific Report Math ─────────────────────────────────────
    report_exists = result.get('report_exists', False)
    report_mtime = result.get('report_mtime', 0)
    report_b64 = result.get('report_b64', '')
    
    if report_exists and report_mtime > task_start and report_b64:
        try:
            report_text = base64.b64decode(report_b64).decode('utf-8', errors='ignore')
            valid_math_pairs = check_report_math(report_text)
            
            if valid_math_pairs >= 4:
                score += 15
                feedback.append(f"Report Math: Found {valid_math_pairs} valid Airmass computations")
            elif valid_math_pairs > 0:
                score += int((valid_math_pairs / 4.0) * 15)
                feedback.append(f"Report Math: Found {valid_math_pairs} valid Airmass computations")
            else:
                feedback.append("Report Math: Could not verify Airmass = 1/sin(Alt) relationships")
        except Exception as e:
            feedback.append(f"Error reading report: {e}")
    else:
        feedback.append("Scientific report missing or not generated during task")

    # Pass requires >=70 points AND at least 3 distinct targets with Alt > 20
    key_constraints_met = (targets_above_horizon >= 3 and num_distinct >= 3)
    passed = (score >= 70) and key_constraints_met
    
    if not key_constraints_met:
        feedback.append("CRITICAL FAILURE: Did not observe enough distinct targets above 20 deg altitude.")

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }