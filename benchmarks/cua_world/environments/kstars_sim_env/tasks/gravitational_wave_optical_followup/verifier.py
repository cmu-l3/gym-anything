#!/usr/bin/env python3
"""
Verifier for gravitational_wave_optical_followup task.

Occupation: Astronomer / Multi-Messenger Astrophysicist
Context: GW optical counterpart search (kilonova) among 3 candidate galaxies.

Criteria (100 pts total, pass >= 65):
1. B-band Coverage: >=1 valid B-band FITS in all 3 galaxy dirs (15 pts)
2. R-band Coverage: >=1 valid R-band FITS in all 3 galaxy dirs (15 pts)
3. Telescope Pointing: Within 3° of Hydra-Centaurus region (RA 13.1h, Dec -23.5°) (15 pts)
4. GCN Report Created: exists and created during task (15 pts)
5. Report Mentions Targets: NGC 4993, ESO 508, NGC 4970 (20 pts)
6. Data Analysis Accuracy: Report text contains RMS values matching the TRUE RMS calculated from the agent's R-band FITS ± 5% tolerance (20 pts)
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

# Target Region Coordinates (Hydra-Centaurus approximate center of the 3 galaxies)
TARGET_RA = 13.15      # hours
TARGET_DEC = -23.6     # degrees
REGION_TOL_DEG = 3.0


def angular_separation_deg(ra1_h, dec1_deg, ra2_h, dec2_deg):
    ra1 = math.radians(ra1_h * 15.0)
    dec1 = math.radians(dec1_deg)
    ra2 = math.radians(ra2_h * 15.0)
    dec2 = math.radians(dec2_deg)
    cos_sep = (math.sin(dec1) * math.sin(dec2) +
               math.cos(dec1) * math.cos(dec2) * math.cos(ra1 - ra2))
    cos_sep = max(-1.0, min(1.0, cos_sep))
    return math.degrees(math.acos(cos_sep))


def verify_gw_followup(traj, env_info, task_info):
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

    # Filter out stale files & get the true RMS values for R-band images
    fits_files = result.get('fits_files', [])
    valid_fits = [f for f in fits_files if f.get('mtime', 0) > task_start and f.get('size', 0) > 2048]
    
    galaxies = ['ngc4993', 'eso508_g019', 'ngc4970']
    
    b_coverage = 0
    r_coverage = 0
    true_rms_values = []
    
    for gal in galaxies:
        has_b = False
        has_r = False
        for f in valid_fits:
            if gal in f.get('dir', '').lower():
                filt = f.get('filter', '').upper()
                if 'B' in filt or filt == '3':
                    has_b = True
                if 'R' in filt or filt == '4':
                    has_r = True
                    rms = f.get('true_rms', -1.0)
                    if rms > 0:
                        true_rms_values.append(rms)
        
        if has_b: b_coverage += 1
        if has_r: r_coverage += 1

    # ── 1. B-band Coverage (15 pts) ───────────────────────────────────
    if b_coverage == 3:
        score += 15
        feedback.append("B-band coverage complete for all 3 candidates")
    elif b_coverage > 0:
        score += 5 * b_coverage
        feedback.append(f"B-band coverage partial ({b_coverage}/3)")
    else:
        feedback.append("No valid B-band frames found")

    # ── 2. R-band Coverage (15 pts) ───────────────────────────────────
    if r_coverage == 3:
        score += 15
        feedback.append("R-band coverage complete for all 3 candidates")
    elif r_coverage > 0:
        score += 5 * r_coverage
        feedback.append(f"R-band coverage partial ({r_coverage}/3)")
    else:
        feedback.append("No valid R-band frames found")

    # ── 3. Telescope Pointing (15 pts) ────────────────────────────────
    try:
        final_ra = float(result.get('final_ra', -1))
        final_dec = float(result.get('final_dec', -999))
    except (ValueError, TypeError):
        final_ra, final_dec = -1.0, -999.0

    if final_ra > 0 and final_dec > -900:
        sep_deg = angular_separation_deg(final_ra, final_dec, TARGET_RA, TARGET_DEC)
        if sep_deg <= REGION_TOL_DEG:
            score += 15
            feedback.append(f"Telescope pointing OK (within {sep_deg:.1f}° of targets)")
        else:
            feedback.append(f"Telescope far from target region (sep {sep_deg:.1f}°)")
    else:
        feedback.append("Could not determine final telescope coordinates")

    # ── 4. GCN Report Existence (15 pts) ──────────────────────────────
    report_exists = result.get('report_exists', False)
    report_mtime = result.get('report_mtime', 0)
    report_b64 = result.get('report_b64', '')
    report_text = ''
    
    if report_exists and report_mtime > task_start:
        score += 15
        feedback.append("GCN report created during task")
    else:
        feedback.append("GCN report missing or not updated during task")

    if report_b64:
        try:
            report_text = base64.b64decode(report_b64).decode('utf-8', errors='ignore')
        except:
            pass

    # ── 5. Targets Mentioned (20 pts) ─────────────────────────────────
    if report_text:
        text_lower = report_text.lower()
        mentions = 0
        if "4993" in text_lower: mentions += 1
        if "508" in text_lower: mentions += 1
        if "4970" in text_lower: mentions += 1
        
        if mentions == 3:
            score += 20
            feedback.append("Report mentions all 3 candidate galaxies")
        elif mentions > 0:
            score += 6 * mentions
            feedback.append(f"Report mentions {mentions}/3 galaxies")
        else:
            feedback.append("Report does not identify the candidate galaxies")

    # ── 6. Data Analysis Accuracy (20 pts) ────────────────────────────
    # Extract all numbers from the report text
    reported_numbers = []
    if report_text:
        for match in re.findall(r'[-+]?\d*\.\d+|\d+', report_text):
            try:
                reported_numbers.append(float(match))
            except ValueError:
                pass

    analysis_score = 0
    matched_rms_count = 0
    if true_rms_values and reported_numbers:
        for true_rms in true_rms_values:
            # Check if any reported number is within 5% of the true calculated RMS
            if any(abs(n - true_rms) / max(true_rms, 1e-5) <= 0.05 for n in reported_numbers):
                matched_rms_count += 1
                
        # Assign ~6.6 pts per correctly identified and reported RMS
        if matched_rms_count == 3:
            analysis_score = 20
        else:
            analysis_score = int((matched_rms_count / 3.0) * 20)
            
        score += analysis_score
        feedback.append(f"Accurate RMS analysis: {matched_rms_count}/3 values matched dynamically")
    else:
        if not true_rms_values:
            feedback.append("No valid R-band FITS captured to analyze")
        elif not reported_numbers:
            feedback.append("No numeric data found in GCN report")
        else:
            feedback.append("Reported numbers do not match true image RMS")

    # ── Final Verdict ─────────────────────────────────────────────────
    passed = score >= 65 and matched_rms_count > 0 and b_coverage > 0 and r_coverage > 0
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback),
        "details": {
            "b_coverage": b_coverage,
            "r_coverage": r_coverage,
            "true_rms_values": true_rms_values,
            "matched_rms": matched_rms_count
        }
    }