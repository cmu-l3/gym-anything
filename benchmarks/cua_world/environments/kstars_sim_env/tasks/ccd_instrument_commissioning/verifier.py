#!/usr/bin/env python3
"""
Verifier for ccd_instrument_commissioning task.

Criteria (100 pts total, pass >= 60):
1. Telescope pointed at M45 (RA ~3.79h, Dec ~24.116°)            - 15 pts
2. Test 1: 6 frames in filters/ covering 6 distinct slots        - 30 pts (5 pts per slot)
3. Test 2: 4 frames in binning/ with 1x1, 2x2, 3x3, 4x4          - 30 pts (7.5 pts per bin)
4. Test 3: 1 frame in roi/ with 1024x1024 size and 1x1 binning   - 15 pts
5. Report file created                                           - 10 pts

Anti-gaming: FITS files are only counted if their mtime > task_start and size > 0.
This intentionally rejects the pre-seeded distractor files in the binning directory.
"""

import json
import os
import math
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# M45 coordinates
TARGET_RA = 3.79     # hours
TARGET_DEC = 24.116  # degrees
COORD_TOL_ARCMIN = 60.0


def angular_separation_deg(ra1_h, dec1_deg, ra2_h, dec2_deg):
    ra1 = math.radians(ra1_h * 15.0)
    dec1 = math.radians(dec1_deg)
    ra2 = math.radians(ra2_h * 15.0)
    dec2 = math.radians(dec2_deg)
    cos_sep = (math.sin(dec1) * math.sin(dec2) +
               math.cos(dec1) * math.cos(dec2) * math.cos(ra1 - ra2))
    cos_sep = max(-1.0, min(1.0, cos_sep))
    return math.degrees(math.acos(cos_sep))


def verify_ccd_instrument_commissioning(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System error: copy_from_env unavailable"}

    # Load result
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

    # Filter out files created before the task started or empty stubs
    valid_fits = [f for f in fits_files if f.get('mtime', 0) > task_start and f.get('size', 0) > 2048]

    # ── Criterion 1: Target Pointing (15 pts) ─────────────────────────
    try:
        final_ra = float(result.get('final_ra', -1))
        final_dec = float(result.get('final_dec', -999))
    except (ValueError, TypeError):
        final_ra, final_dec = -1.0, -999.0

    if final_ra >= 0 and final_dec > -900:
        sep_deg = angular_separation_deg(final_ra, final_dec, TARGET_RA, TARGET_DEC)
        sep_arcmin = sep_deg * 60.0
        if sep_arcmin <= COORD_TOL_ARCMIN:
            score += 15
            feedback.append(f"Telescope pointing OK (sep {sep_arcmin:.1f}' from M45)")
        else:
            feedback.append(f"Telescope not at M45 (sep {sep_arcmin:.1f}')")
    else:
        feedback.append("Could not read final telescope coordinates.")

    # ── Criterion 2: Filter Test (30 pts) ─────────────────────────────
    # Check `filters/` directory for distinct filter values
    filter_frames = [f for f in valid_fits if f.get('dir') == 'filters']
    distinct_filters = set()
    for f in filter_frames:
        filt_val = f.get('filter', '')
        if filt_val:
            distinct_filters.add(filt_val.upper())

    found_filters_count = len(distinct_filters)
    filter_pts = min(found_filters_count * 5, 30)
    score += filter_pts
    if found_filters_count >= 6:
        feedback.append("Filter test complete: 6 distinct filters found.")
    elif found_filters_count > 0:
        feedback.append(f"Filter test partial: {found_filters_count}/6 distinct filters found.")
    else:
        feedback.append("Filter test failed: no valid frames found in filters/ directory.")

    # ── Criterion 3: Binning Test (30 pts) ────────────────────────────
    # Check `binning/` directory for 1x1, 2x2, 3x3, 4x4
    binning_frames = [f for f in valid_fits if f.get('dir') == 'binning']
    found_bins = set()
    for f in binning_frames:
        xb = f.get('xbin')
        yb = f.get('ybin')
        # Standard assumption: symmetric binning
        if xb == yb and xb in [1, 2, 3, 4]:
            found_bins.add(xb)

    binning_pts = int(len(found_bins) * 7.5)
    score += binning_pts
    if len(found_bins) == 4:
        feedback.append("Binning test complete: 1x1, 2x2, 3x3, 4x4 found.")
    elif len(found_bins) > 0:
        bins_str = ", ".join([f"{b}x{b}" for b in sorted(found_bins)])
        feedback.append(f"Binning test partial: found {bins_str}.")
    else:
        feedback.append("Binning test failed: no valid binned frames found.")

    # ── Criterion 4: ROI / Subframe Test (15 pts) ─────────────────────
    # Check `roi/` directory for 1024x1024 size
    roi_frames = [f for f in valid_fits if f.get('dir') == 'roi']
    roi_success = False
    for f in roi_frames:
        if f.get('naxis1') == 1024 and f.get('naxis2') == 1024 and f.get('xbin') == 1:
            roi_success = True
            break

    if roi_success:
        score += 15
        feedback.append("ROI test complete: 1024x1024 subframe found.")
    else:
        if len(roi_frames) > 0:
            feedback.append("ROI test failed: frames found but dimensions were not exactly 1024x1024.")
        else:
            feedback.append("ROI test failed: no frames found in roi/ directory.")

    # ── Criterion 5: Report File (10 pts) ─────────────────────────────
    report_exists = result.get('report_exists', False)
    report_mtime = result.get('report_mtime', 0)

    if report_exists and report_mtime > task_start:
        score += 10
        feedback.append("Commissioning report created.")
    elif report_exists:
        feedback.append("Report exists but pre-dates task start (not created by agent).")
    else:
        feedback.append("Commissioning report missing.")

    # ── Final Verdict ─────────────────────────────────────────────────
    passed = score >= 60 and (len(found_bins) >= 2 or roi_success)

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback),
        "details": {
            "filters_found": list(distinct_filters),
            "bins_found": list(found_bins),
            "roi_success": roi_success
        }
    }