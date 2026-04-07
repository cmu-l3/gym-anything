#!/usr/bin/env python3
"""
Verifier for aavso_variable_star_campaign task.

Occupation: Astronomer / AAVSO Variable Star Observer
Context: Dwarf nova SS Cygni outburst monitoring campaign

Criteria (100 pts total, pass >= 60):
1. FITS images captured in correct directory (25 pts)
2. V-band filter used (15 pts)
3. Telescope pointed at SS Cyg (20 pts)
4. AAVSO report file exists and was created during task (15 pts)
5. Report format and content valid (25 pts)
"""

import json
import base64
import os
import math
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# SS Cygni true coordinates
SS_CYG_RA = 21.7119   # hours
SS_CYG_DEC = 43.5861  # degrees
COORD_TOLERANCE_ARCMIN = 20.0  # generous tolerance


def angular_separation_deg(ra1_h, dec1_deg, ra2_h, dec2_deg):
    """Return angular separation in degrees between two equatorial coordinates."""
    ra1 = math.radians(ra1_h * 15.0)
    dec1 = math.radians(dec1_deg)
    ra2 = math.radians(ra2_h * 15.0)
    dec2 = math.radians(dec2_deg)
    cos_sep = (math.sin(dec1) * math.sin(dec2) +
               math.cos(dec1) * math.cos(dec2) * math.cos(ra1 - ra2))
    cos_sep = max(-1.0, min(1.0, cos_sep))
    return math.degrees(math.acos(cos_sep))


def verify_aavso_variable_star_campaign(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System error: copy_from_env unavailable"}

    metadata = task_info.get('metadata', {})
    min_fits = metadata.get('min_fits_count', 8)
    req_filter_slot = metadata.get('required_filter_slot', 2)
    coord_tol_arcmin = metadata.get('coordinate_tolerance_arcmin', 20)

    # ── Load result file ──────────────────────────────────────────────
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

    # ── Criterion 1: FITS images (25 pts) ────────────────────────────
    fits_files = result.get('fits_files', [])
    fits_count_session = result.get('fits_count_session', 0)

    # Anti-gaming: count only files created AFTER task start
    valid_fits = [f for f in fits_files
                  if f.get('mtime', 0) > task_start and f.get('size', 0) > 2048]
    valid_count = len(valid_fits)

    if valid_count >= min_fits:
        score += 25
        feedback.append(f"captured {valid_count} FITS images in session directory")
    elif valid_count >= 4:
        score += 12
        feedback.append(f"captured {valid_count} FITS images (need {min_fits})")
    elif valid_count >= 1:
        score += 5
        feedback.append(f"only {valid_count} FITS image(s) — need {min_fits}")
    else:
        feedback.append(f"no valid FITS images found in session directory")

    # ── Criterion 2: V-band filter used (15 pts) ─────────────────────
    filter_slot = result.get('current_filter_slot', -1)
    fits_filter = result.get('fits_filter_used', '').strip().upper()

    filter_correct = False
    if filter_slot == req_filter_slot:
        filter_correct = True
    elif 'V' in fits_filter or fits_filter in ('V', 'VBAND', 'JOHNSON-V', 'BESSEL-V'):
        filter_correct = True

    if filter_correct:
        score += 15
        feedback.append("V-band filter correctly used")
    else:
        feedback.append(f"V-band filter not verified (slot={filter_slot}, FITS FILTER='{fits_filter}')")

    # ── Criterion 3: Telescope pointed at SS Cyg (20 pts) ─────────────
    try:
        final_ra = float(result.get('final_ra', -1))
        final_dec = float(result.get('final_dec', -999))
    except (ValueError, TypeError):
        final_ra, final_dec = -1.0, -999.0

    coord_ok = False
    if final_ra > 0 and final_dec > -900:
        sep_deg = angular_separation_deg(final_ra, final_dec, SS_CYG_RA, SS_CYG_DEC)
        sep_arcmin = sep_deg * 60.0
        if sep_arcmin <= coord_tol_arcmin:
            score += 20
            feedback.append(f"telescope pointed at SS Cyg (separation {sep_arcmin:.1f}')")
            coord_ok = True
        elif sep_arcmin <= coord_tol_arcmin * 3:
            score += 8
            feedback.append(f"telescope near SS Cyg area (separation {sep_arcmin:.1f}')")
        else:
            feedback.append(f"telescope not at SS Cyg (separation {sep_arcmin:.1f}' from target)")
    else:
        feedback.append("could not read telescope coordinates")

    # ── Criterion 4: Report file exists (15 pts) ──────────────────────
    report_exists = result.get('report_exists', False)
    report_mtime = result.get('report_mtime', 0)
    report_during_task = report_exists and (report_mtime > task_start)

    if report_during_task:
        score += 15
        feedback.append("AAVSO report file created during task")
    elif report_exists:
        score += 5
        feedback.append("report file exists but has old timestamp (pre-task)")
    else:
        feedback.append("AAVSO report file not found at ~/Documents/aavso_report.txt")

    # ── Criterion 5: Report content valid (25 pts) ───────────────────
    report_b64 = result.get('report_content_b64', '')
    report_valid = False
    if report_b64:
        try:
            report_text = base64.b64decode(report_b64).decode('utf-8', errors='ignore')
            # Unescape if needed (JSON double-escaping)
            report_text = report_text.replace('\\n', '\n').replace('\\t', '\t')

            has_ss_cyg = 'SS CYG' in report_text.upper() or 'SS_CYG' in report_text.upper() or 'SSCYG' in report_text.upper()
            has_filter_v = ',V,' in report_text or ' V ' in report_text or 'FILT=V' in report_text.upper() or ',V\n' in report_text
            has_aavso_headers = ('#TYPE' in report_text.upper() or
                                 '#OBSCODE' in report_text.upper() or
                                 '#DATE' in report_text.upper() or
                                 'AAVSO' in report_text.upper())
            has_magnitude = any(c.isdigit() for c in report_text)

            if has_ss_cyg and has_aavso_headers and has_filter_v:
                score += 25
                report_valid = True
                feedback.append("report contains valid AAVSO format with SS Cyg entry and V-band")
            elif has_ss_cyg and has_aavso_headers:
                score += 18
                feedback.append("report has AAVSO headers and SS Cyg entry (filter unclear)")
            elif has_ss_cyg:
                score += 10
                feedback.append("report mentions SS Cyg but missing AAVSO format headers")
            elif has_aavso_headers:
                score += 5
                feedback.append("report has AAVSO headers but missing SS Cyg target entry")
            else:
                feedback.append("report content does not match AAVSO format")
        except Exception as e:
            feedback.append(f"report decode error: {e}")
    else:
        feedback.append("report file empty or unreadable")

    # ── Final verdict ─────────────────────────────────────────────────
    passed = (score >= 60) and coord_ok and (valid_count >= min_fits)

    return {
        "passed": passed,
        "score": score,
        "feedback": "; ".join(feedback)
    }
