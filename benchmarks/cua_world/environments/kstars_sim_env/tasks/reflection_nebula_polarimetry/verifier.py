#!/usr/bin/env python3
"""
Verifier for reflection_nebula_polarimetry task.

Occupation: Postdoctoral Researcher / Astronomer
Context: Measuring Stokes parameters using linear polarimetry of M78.
         Frames must be saved to 4 distinct angles: 000, 045, 090, 135.

Criteria (100 pts total, pass >= 60):
1. Telescope pointed at M78 (within 20 arcmin)                      - 15 pts
2. Angle 000 frames (>=3 valid FITS, 120s exposure, correct filter) - 15 pts
3. Angle 045 frames (>=3 valid FITS, 120s exposure, correct filter) - 15 pts
4. Angle 090 frames (>=3 valid FITS, 120s exposure, correct filter) - 15 pts
5. Angle 135 frames (>=3 valid FITS, 120s exposure, correct filter) - 15 pts
6. Sky context image generated (m78_context.png)                    - 15 pts
7. Stokes observation log created with expected text elements       - 10 pts

Anti-gaming: Decoy files in angle_000 have pre-task timestamps and will be ignored.
"""

import json
import base64
import os
import math
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# M78 actual coordinates
TARGET_RA = 5.780   # 05h 46m 46.7s -> ~5.780h
TARGET_DEC = 0.014  # +00d 00m 50s -> ~0.014 deg
COORD_TOL_ARCMIN = 20.0


def angular_separation_deg(ra1_h, dec1_deg, ra2_h, dec2_deg):
    ra1 = math.radians(ra1_h * 15.0)
    dec1 = math.radians(dec1_deg)
    ra2 = math.radians(ra2_h * 15.0)
    dec2 = math.radians(dec2_deg)
    cos_sep = (math.sin(dec1) * math.sin(dec2) +
               math.cos(dec1) * math.cos(dec2) * math.cos(ra1 - ra2))
    cos_sep = max(-1.0, min(1.0, cos_sep))
    return math.degrees(math.acos(cos_sep))


def verify_reflection_nebula_polarimetry(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System error: copy_from_env unavailable"}

    metadata = task_info.get('metadata', {})
    min_fits = metadata.get('min_fits_per_angle', 3)

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

    # ── Criterion 1: Telescope Pointing (15 pts) ────────────────────────
    try:
        final_ra = float(result.get('final_ra', -1))
        final_dec = float(result.get('final_dec', -999))
    except (ValueError, TypeError):
        final_ra, final_dec = -1.0, -999.0

    if final_ra > 0 and final_dec > -900:
        sep_deg = angular_separation_deg(final_ra, final_dec, TARGET_RA, TARGET_DEC)
        sep_arcmin = sep_deg * 60.0
        if sep_arcmin <= COORD_TOL_ARCMIN:
            score += 15
            feedback.append(f"Telescope pointing OK (sep {sep_arcmin:.1f}')")
        elif sep_arcmin <= COORD_TOL_ARCMIN * 3:
            score += 5
            feedback.append(f"Telescope near target area (sep {sep_arcmin:.1f}')")
        else:
            feedback.append(f"Telescope NOT at M78 (sep {sep_arcmin:.1f}')")
    else:
        feedback.append("Could not verify telescope coordinates")

    # ── Criteria 2-5: FITS sequences (15 pts each) ──────────────────────
    fits_files = result.get('fits_files', [])
    valid_fits = [f for f in fits_files
                  if f.get('mtime', 0) > task_start and f.get('size', 0) > 2048]

    def check_sequence(angle_dir, expected_filter, expected_exptime=120):
        """Returns points (0 to 15) and feedback string for an angle directory."""
        # Find frames matching the directory and roughly the exptime
        frames = [f for f in valid_fits if f.get('dir') == angle_dir and f.get('exptime', -1) >= expected_exptime * 0.9]
        
        count = len(frames)
        # Check filter if FITS headers were successfully read, otherwise rely on directory routing
        filter_match = True
        if count > 0 and frames[0].get('filter'):
            if expected_filter not in frames[0].get('filter', ''):
                filter_match = False
        
        if count >= min_fits and filter_match:
            return 15, f"{angle_dir}: {count} valid frames"
        elif count >= min_fits and not filter_match:
            return 10, f"{angle_dir}: {count} frames, but filter header discrepancy"
        elif count > 0:
            return 5, f"{angle_dir}: incomplete sequence ({count}/{min_fits})"
        else:
            return 0, f"{angle_dir}: missing valid frames"

    # Evaluate the 4 angles
    pts, fb = check_sequence('angle_000', 'Pol_000')
    score += pts; feedback.append(fb)

    pts, fb = check_sequence('angle_045', 'Pol_045')
    score += pts; feedback.append(fb)

    pts, fb = check_sequence('angle_090', 'Pol_090')
    score += pts; feedback.append(fb)

    pts, fb = check_sequence('angle_135', 'Pol_135')
    score += pts; feedback.append(fb)

    # ── Criterion 6: Context Image (15 pts) ────────────────────────────
    if result.get('context_image_exists', False):
        if result.get('context_image_size', 0) > 10240: # >10KB means real image
            score += 15
            feedback.append("Context image successfully generated")
        else:
            score += 5
            feedback.append("Context image found but file size too small")
    else:
        feedback.append("Context image missing or not updated")

    # ── Criterion 7: Observation Log (10 pts) ──────────────────────────
    log_exists = result.get('log_exists', False)
    log_mtime = result.get('log_mtime', 0)

    if log_exists and log_mtime > task_start:
        log_b64 = result.get('log_b64', '')
        try:
            log_text = base64.b64decode(log_b64).decode('utf-8', errors='ignore').upper()
            if 'M78' in log_text and '000' in log_text and '045' in log_text and '090' in log_text and '135' in log_text:
                score += 10
                feedback.append("Observation log complete and accurate")
            else:
                score += 5
                feedback.append("Observation log created but missing required details")
        except Exception:
            score += 2
            feedback.append("Observation log present but could not be parsed")
    elif log_exists:
        feedback.append("Observation log exists but has an old timestamp")
    else:
        feedback.append("Observation log missing")

    passed = score >= 60
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }