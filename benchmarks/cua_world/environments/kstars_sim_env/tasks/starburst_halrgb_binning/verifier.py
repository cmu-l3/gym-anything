#!/usr/bin/env python3
"""
Verifier for starburst_halrgb_binning task.

Occupation: Astrophysicist / Observatory Technician
Context: Hybrid HaLRGB sequence on M82 with variable binning and exposures.

Criteria (100 pts total, pass >= 65):
1. Telescope pointed at M82 (within 15 arcmin, ignoring M81 distractor) - 20 pts
2. L-band frames (>=5 in L/, 1x1 binning, >=10s exposure) - 15 pts
3. RGB frames (>=5 each in R/, G/, B/, 2x2 binning, >=10s exposure) - 20 pts
4. Ha frames (>=5 in Ha/, 2x2 binning, >=60s exposure) - 25 pts
5. Sky capture exists - 10 pts
6. Observation log exists - 10 pts

Anti-gaming:
- Target coordinate verification ensures agent didn't stay parked at M81.
- Stale Ha frames have pre-task timestamps and are 1x1 binned; they will not count.
"""

import json
import os
import math
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# M82 coordinates
M82_RA = 9.9311      # hours
M82_DEC = 69.6797    # degrees
COORD_TOL_ARCMIN = 15.0


def angular_separation_deg(ra1_h, dec1_deg, ra2_h, dec2_deg):
    ra1 = math.radians(ra1_h * 15.0)
    dec1 = math.radians(dec1_deg)
    ra2 = math.radians(ra2_h * 15.0)
    dec2 = math.radians(dec2_deg)
    cos_sep = (math.sin(dec1) * math.sin(dec2) +
               math.cos(dec1) * math.cos(dec2) * math.cos(ra1 - ra2))
    cos_sep = max(-1.0, min(1.0, cos_sep))
    return math.degrees(math.acos(cos_sep))


def verify_starburst_halrgb_binning(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System error: copy_from_env unavailable"}

    metadata = task_info.get('metadata', {})
    min_frames = metadata.get('min_fits_per_filter', 5)

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

    # ── Verify Telescope Position (20 pts) ────────────────────────────
    coord_ok = False
    try:
        final_ra = float(result.get('final_ra', -1))
        final_dec = float(result.get('final_dec', -999))
    except (ValueError, TypeError):
        final_ra, final_dec = -1.0, -999.0

    if final_ra > 0 and final_dec > -900:
        sep_deg = angular_separation_deg(final_ra, final_dec, M82_RA, M82_DEC)
        sep_arcmin = sep_deg * 60.0
        if sep_arcmin <= COORD_TOL_ARCMIN:
            score += 20
            coord_ok = True
            feedback.append(f"Telescope correctly slewed to M82 (sep {sep_arcmin:.1f}')")
        else:
            feedback.append(f"Telescope is {sep_arcmin:.1f}' from M82 target! (Remained at M81?)")
    else:
        feedback.append("Could not read telescope coordinates.")

    # ── Parse and Filter FITS files ───────────────────────────────────
    fits_files = result.get('fits_files', [])
    valid_fits = [f for f in fits_files
                  if f.get('mtime', 0) > task_start and f.get('size', 0) > 2048]

    def count_valid(dirname, expected_xbin, min_exptime):
        count = 0
        for f in valid_fits:
            if f.get('dir') == dirname:
                if f.get('xbin') == expected_xbin and f.get('exptime') >= min_exptime - 1.0:
                    count += 1
        return count

    # L-band: 1x1, >=10s
    l_count = count_valid('L', 1, 10.0)
    # RGB: 2x2, >=10s
    r_count = count_valid('R', 2, 10.0)
    g_count = count_valid('G', 2, 10.0)
    b_count = count_valid('B', 2, 10.0)
    # Ha: 2x2, >=60s
    ha_count = count_valid('Ha', 2, 60.0)

    # ── L-band frames (15 pts) ────────────────────────────────────────
    if l_count >= min_frames:
        score += 15
        feedback.append(f"L frames: {l_count} valid (1x1 binning, >=10s)")
    elif l_count > 0:
        score += 7
        feedback.append(f"L frames: {l_count}/{min_frames} valid")
    else:
        feedback.append("L frames: Missing or incorrect binning/exposure")

    # ── RGB frames (20 pts) ───────────────────────────────────────────
    rgb_total = min(r_count, min_frames) + min(g_count, min_frames) + min(b_count, min_frames)
    if r_count >= min_frames and g_count >= min_frames and b_count >= min_frames:
        score += 20
        feedback.append("RGB frames: All complete (2x2 binning, >=10s)")
    elif rgb_total > 0:
        score += int((rgb_total / (min_frames * 3)) * 20)
        feedback.append(f"RGB frames: Partial ({r_count}R, {g_count}G, {b_count}B valid)")
    else:
        feedback.append("RGB frames: Missing or incorrect parameters")

    # ── Ha frames (25 pts) ────────────────────────────────────────────
    if ha_count >= min_frames:
        score += 25
        feedback.append(f"Ha frames: {ha_count} valid (2x2 binning, >=60s, stale ignored)")
    elif ha_count > 0:
        score += 12
        feedback.append(f"Ha frames: {ha_count}/{min_frames} valid")
    else:
        feedback.append("Ha frames: Missing or incorrect (stale files correctly ignored)")

    # ── Additional deliverables (20 pts) ──────────────────────────────
    if result.get('sky_capture_exists', False):
        score += 10
        feedback.append("Sky capture exists")
    else:
        feedback.append("Sky capture missing")

    if result.get('log_exists', False):
        score += 10
        feedback.append("Observation log exists")
    else:
        feedback.append("Observation log missing")

    # ── Final determination ───────────────────────────────────────────
    key_criteria_met = coord_ok and (ha_count >= min_frames)
    passed = (score >= 65) and key_criteria_met

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback),
        "details": {
            "counts": {"L": l_count, "R": r_count, "G": g_count, "B": b_count, "Ha": ha_count},
            "coord_ok": coord_ok,
            "key_criteria_met": key_criteria_met
        }
    }