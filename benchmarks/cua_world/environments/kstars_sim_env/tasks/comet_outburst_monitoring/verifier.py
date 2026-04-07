#!/usr/bin/env python3
"""
Verifier for comet_outburst_monitoring task.

Occupation: Astronomer / Comet Observer
Context: 29P/Schwassmann-Wachmann 1 outburst monitoring

Criteria (100 pts total, pass >= 60):
1. R-band FITS images (≥5 new frames in 29P/R/)                 - 20 pts
2. V-band FITS images (≥3 new frames in 29P/V/)                 - 15 pts
3. Telescope at 29P field (RA 6.2561h, Dec +23.0717°)           - 20 pts
4. Finding chart exists (finding_chart.png, >50KB)              - 10 pts
5. ICQ report exists and created during task                    - 10 pts
6. Report names 29P                                             - 10 pts
7. Report has magnitude estimate                                - 5 pts
8. Report has coma diameter & DC                                - 5 pts
9. Report has headers (OBS/TEL)                                 - 5 pts

Anti-gaming:
- Mtime checks against task start time.
- Stale 2024 FITS files ignored.
- Report content parsed for specifics.
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

# 29P Coordinates
COMET_RA = 6.2561    # hours
COMET_DEC = 23.0717  # degrees
COORD_TOL_ARCMIN = 30.0


def angular_separation_deg(ra1_h, dec1_deg, ra2_h, dec2_deg):
    ra1 = math.radians(ra1_h * 15.0)
    dec1 = math.radians(dec1_deg)
    ra2 = math.radians(ra2_h * 15.0)
    dec2 = math.radians(dec2_deg)
    cos_sep = (math.sin(dec1) * math.sin(dec2) +
               math.cos(dec1) * math.cos(dec2) * math.cos(ra1 - ra2))
    cos_sep = max(-1.0, min(1.0, cos_sep))
    return math.degrees(math.acos(cos_sep))


def verify_comet_outburst_monitoring(traj, env_info, task_info):
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

    # ── FITS Validation ────────────────────────────────────────────────
    fits_files = result.get('fits_files', [])
    valid_fits = [f for f in fits_files
                  if f.get('mtime', 0) > task_start and f.get('size', 0) > 2048]

    def count_in_dir(dirname):
        """Count valid FITS matching a specific directory."""
        return sum(1 for f in valid_fits if f.get('dir', '').upper() == dirname.upper())

    r_count = count_in_dir('R')
    v_count = count_in_dir('V')

    # Criterion 1: R-band images (20 pts)
    if r_count >= 5:
        score += 20
        feedback.append(f"R-band: {r_count} valid frames")
    elif r_count >= 2:
        score += 10
        feedback.append(f"R-band: {r_count}/5 frames")
    elif r_count >= 1:
        score += 5
        feedback.append(f"R-band: only {r_count} frame")
    else:
        feedback.append("R-band: no new frames in 29P/R/")

    # Criterion 2: V-band images (15 pts)
    if v_count >= 3:
        score += 15
        feedback.append(f"V-band: {v_count} valid frames")
    elif v_count >= 1:
        score += 7
        feedback.append(f"V-band: {v_count}/3 frames")
    else:
        feedback.append("V-band: no new frames in 29P/V/")

    # ── Telescope Position (20 pts) ────────────────────────────────────
    try:
        final_ra = float(result.get('final_ra', -1))
        final_dec = float(result.get('final_dec', -999))
    except (ValueError, TypeError):
        final_ra, final_dec = -1.0, -999.0

    if final_ra > 0 and final_dec > -900:
        sep_deg = angular_separation_deg(final_ra, final_dec, COMET_RA, COMET_DEC)
        sep_arcmin = sep_deg * 60.0
        if sep_arcmin <= COORD_TOL_ARCMIN:
            score += 20
            feedback.append(f"Telescope at 29P (sep {sep_arcmin:.1f}')")
        elif sep_arcmin <= COORD_TOL_ARCMIN * 3:
            score += 10
            feedback.append(f"Telescope near 29P area (sep {sep_arcmin:.1f}')")
        else:
            feedback.append(f"Telescope not at 29P (sep {sep_arcmin:.1f}')")
    else:
        feedback.append("Could not read telescope coordinates")

    # ── Finding Chart (10 pts) ─────────────────────────────────────────
    chart_exists = result.get('finding_chart_exists', False)
    chart_size = result.get('finding_chart_size', 0)
    
    if chart_exists and chart_size > 50000:
        score += 10
        feedback.append("Finding chart created successfully")
    elif chart_exists:
        score += 5
        feedback.append("Finding chart created but file size is suspiciously small")
    else:
        feedback.append("Finding chart not found or invalid")

    # ── ICQ Report Verification (35 pts total) ─────────────────────────
    report_exists = result.get('report_exists', False)
    report_mtime = result.get('report_mtime', 0)
    report_b64 = result.get('report_b64', '')
    
    if report_exists and report_mtime > task_start:
        score += 10
        feedback.append("ICQ report file created")
        
        try:
            report_text = base64.b64decode(report_b64).decode('utf-8', errors='ignore')
            report_upper = report_text.upper()
            
            # Name check (10 pts)
            if '29P' in report_upper or 'SCHWASSMANN' in report_upper:
                score += 10
                feedback.append("Report names target (29P)")
            else:
                feedback.append("Report missing comet designation")
                
            # Magnitude check (5 pts) - looking for any number between 10.0 and 15.9
            if re.search(r'\b1[0-5](?:\.\d+)?\b', report_text):
                score += 5
                feedback.append("Report contains magnitude estimate")
            else:
                feedback.append("Report missing magnitude estimate")
                
            # Coma and DC check (5 pts)
            has_coma = bool(re.search(r'(?i)(coma|dia|diameter|0\.\d+)', report_text))
            has_dc = bool(re.search(r'(?i)(DC|condensation)', report_text)) or bool(re.search(r'\b[0-9]\b', report_text))
            if has_coma and has_dc:
                score += 5
                feedback.append("Report contains Coma/DC data")
            else:
                feedback.append("Report missing Coma/DC data")
                
            # Headers check (5 pts)
            if re.search(r'(?i)(OBS|TEL)[^a-z]', report_text):
                score += 5
                feedback.append("Report contains standard headers")
            else:
                feedback.append("Report missing standard headers")
                
        except Exception as e:
            feedback.append(f"Failed to parse report text: {e}")
            
    elif report_exists:
        feedback.append("ICQ report exists but has pre-task timestamp (invalid)")
    else:
        feedback.append("ICQ report not found")

    passed = score >= 60
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }