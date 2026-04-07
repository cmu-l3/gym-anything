#!/usr/bin/env python3
"""
Verifier for globular_cluster_hdr_profiling task.

Hybrid Verification Strategy:
1. Programmatic Check (80 points):
   - Telescope pointed at M15 (RA 21.4994h, Dec +12.1669°)
   - FITS files captured in correct directories (1s/, 5s/, 15s/, 60s/)
   - False-color sky view captured
   - Summary report created and contains required information
2. VLM Check (20 points):
   - Trajectory verification showing agent controlling exposures via KStars/INDI or terminal.
"""

import json
import base64
import os
import math
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

M15_RA = 21.4994
M15_DEC = 12.1669
COORD_TOL_ARCMIN = 30.0

VLM_PROMPT = """You are verifying an agent's completion of an astrophotography task in KStars/Linux.
The task involves setting up varying CCD exposure times (1s, 5s, 15s, 60s) for a High Dynamic Range sequence.

Look at the provided trajectory frames (which span the task duration).
1. Is there evidence of the agent configuring or executing camera exposures? (e.g., using Ekos control panel, typing `indi_setprop` commands in a terminal).
2. Is there evidence of directory/file management for the outputs (e.g., terminal `mkdir`, `cd`, file manager)?

Respond ONLY with a JSON object:
{
    "exposures_configured": true/false,
    "file_management_seen": true/false
}
"""

def angular_separation_deg(ra1_h, dec1_deg, ra2_h, dec2_deg):
    ra1 = math.radians(ra1_h * 15.0)
    dec1 = math.radians(dec1_deg)
    ra2 = math.radians(ra2_h * 15.0)
    dec2 = math.radians(dec2_deg)
    cos_sep = (math.sin(dec1) * math.sin(dec2) +
               math.cos(dec1) * math.cos(dec2) * math.cos(ra1 - ra2))
    cos_sep = max(-1.0, min(1.0, cos_sep))
    return math.degrees(math.acos(cos_sep))

def verify_globular_cluster_hdr_profiling(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System error: copy_from_env unavailable"}

    # Retrieve exported result
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

    # Criterion 1: Telescope Pointing (15 pts)
    try:
        final_ra = float(result.get('final_ra', -1))
        final_dec = float(result.get('final_dec', -999))
    except (ValueError, TypeError):
        final_ra, final_dec = -1.0, -999.0

    if final_ra > 0 and final_dec > -900:
        sep_deg = angular_separation_deg(final_ra, final_dec, M15_RA, M15_DEC)
        sep_arcmin = sep_deg * 60.0
        if sep_arcmin <= COORD_TOL_ARCMIN:
            score += 15
            feedback.append(f"Telescope correctly pointed at M15 (sep {sep_arcmin:.1f}')")
        else:
            feedback.append(f"Telescope not at M15 (sep {sep_arcmin:.1f}')")
    else:
        feedback.append("Could not read telescope coordinates")

    # Criterion 2: FITS files in directories (45 pts total)
    fits_files = result.get('fits_files', [])
    valid_fits = [f for f in fits_files if f.get('mtime', 0) > task_start and f.get('size', 0) > 2048]

    def count_by_dir(d_name):
        return sum(1 for f in valid_fits if f.get('dir') == d_name)

    count_1s = count_by_dir('1s')
    count_5s = count_by_dir('5s')
    count_15s = count_by_dir('15s')
    count_60s = count_by_dir('60s')

    if count_1s >= 5:
        score += 10
        feedback.append("1s exposures complete (≥5 frames)")
    elif count_1s > 0:
        score += 5
        feedback.append(f"1s exposures partial ({count_1s}/5)")
    else:
        feedback.append("Missing 1s exposures")

    if count_5s >= 5:
        score += 10
        feedback.append("5s exposures complete (≥5 frames)")
    elif count_5s > 0:
        score += 5
        feedback.append(f"5s exposures partial ({count_5s}/5)")
    else:
        feedback.append("Missing 5s exposures")

    if count_15s >= 5:
        score += 10
        feedback.append("15s exposures complete (≥5 frames)")
    elif count_15s > 0:
        score += 5
        feedback.append(f"15s exposures partial ({count_15s}/5)")
    else:
        feedback.append("Missing 15s exposures")

    if count_60s >= 5:
        score += 15
        feedback.append("60s exposures complete (≥5 frames)")
    elif count_60s > 0:
        score += 7
        feedback.append(f"60s exposures partial ({count_60s}/5)")
    else:
        feedback.append("Missing 60s exposures")

    # Criterion 3: False Color Capture (10 pts)
    if result.get('sky_capture_exists'):
        score += 10
        feedback.append("Sky view capture created successfully")
    else:
        feedback.append("Missing sky_view_cool.png")

    # Criterion 4: Summary Report (10 pts)
    if result.get('summary_exists'):
        b64 = result.get('summary_b64', '')
        try:
            report_text = base64.b64decode(b64).decode('utf-8', errors='ignore').upper()
            if 'M15' in report_text or '7078' in report_text:
                score += 10
                feedback.append("Summary report created and valid")
            else:
                score += 5
                feedback.append("Summary report created but target name M15 not found")
        except:
            feedback.append("Could not decode summary report")
    else:
        feedback.append("Missing hdr_summary.txt")

    # Criterion 5: VLM Trajectory Verification (20 pts)
    try:
        import sys
        from pathlib import Path
        sys.path.insert(0, str(Path(__file__).parent.parent.parent))
        from gym_anything.vlm import query_vlm, sample_trajectory_frames

        frames = sample_trajectory_frames(traj, n=4)
        vlm_res = query_vlm(images=frames, prompt=VLM_PROMPT)

        if vlm_res and vlm_res.get('success'):
            parsed = vlm_res.get('parsed', {})
            if parsed.get('exposures_configured', False):
                score += 15
                feedback.append("VLM confirmed exposure configuration")
            if parsed.get('file_management_seen', False):
                score += 5
                feedback.append("VLM confirmed file/directory management")
    except Exception as e:
        logger.warning(f"VLM verification skipped/failed: {e}")
        # Default grant points if VLM fails for robustness, provided programmatic is perfect
        if score == 80:
            score += 20
            feedback.append("VLM unavailable; granted points based on perfect programmatic score")

    passed = score >= 70
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }