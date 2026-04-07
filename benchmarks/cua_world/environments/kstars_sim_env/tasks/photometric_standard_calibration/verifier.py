#!/usr/bin/env python3
"""
Verifier for photometric_standard_calibration task.

Occupation: Observatory Technician / Research Astronomer
Context: Landolt standard star field (SA 98) photometric calibration in B, V, R bands.
         Frames must be saved to per-filter subdirectories: sa98/B/, sa98/V/, sa98/R/

Criteria (100 pts total, pass >= 60):
1. B-band FITS images (>=5 in sa98/B/ dir, after task start)   - 20 pts
2. V-band FITS images (>=5 in sa98/V/ dir, after task start)   - 20 pts
3. R-band FITS images (>=5 in sa98/R/ dir, after task start)   - 20 pts
4. Telescope pointed at SA 98 field (within 30 arcmin)         - 20 pts
5. Calibration catalog file created with valid content         - 20 pts

Anti-gaming: pass requires telescope at SA 98 AND >=2 filter sets complete.
Do-nothing score: 0 pts (no files, no coordinates, no catalog).
"""

import json
import base64
import os
import math
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

SA98_RA = 6.86      # hours (06h 51m 36s)
SA98_DEC = -0.283   # degrees
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


def verify_photometric_standard_calibration(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System error: copy_from_env unavailable"}

    metadata = task_info.get('metadata', {})
    min_per_filter = metadata.get('min_fits_per_filter', 5)

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

    # Anti-gaming: only files after task_start with real content
    valid_fits = [f for f in fits_files
                  if f.get('mtime', 0) > task_start and f.get('size', 0) > 2048]

    def count_dir(target_dir):
        """Count valid FITS by directory name (primary) or filter header (fallback)."""
        # Primary: by subdirectory
        by_dir = sum(1 for f in valid_fits if f.get('dir', '').upper() == target_dir.upper())
        if by_dir > 0:
            return by_dir
        # Fallback: by FITS FILTER header (files in root dir)
        by_filt = sum(1 for f in valid_fits
                      if f.get('dir') == 'root' and
                      target_dir.upper() in f.get('filter', '').upper())
        return by_filt

    b_count = count_dir('B')
    v_count = count_dir('V')
    r_count = count_dir('R')

    # ── Criterion 1: B-band (20 pts) ──────────────────────────────────
    if b_count >= min_per_filter:
        score += 20
        feedback.append(f"B-band: {b_count} frames in sa98/B/")
    elif b_count >= 2:
        score += 10
        feedback.append(f"B-band: {b_count}/{min_per_filter} frames")
    elif b_count >= 1:
        score += 5
        feedback.append(f"B-band: only {b_count} frame")
    else:
        feedback.append("B-band: no frames found in sa98/B/")

    # ── Criterion 2: V-band (20 pts) ──────────────────────────────────
    if v_count >= min_per_filter:
        score += 20
        feedback.append(f"V-band: {v_count} frames in sa98/V/")
    elif v_count >= 2:
        score += 10
        feedback.append(f"V-band: {v_count}/{min_per_filter} frames")
    elif v_count >= 1:
        score += 5
        feedback.append(f"V-band: only {v_count} frame")
    else:
        feedback.append("V-band: no frames found in sa98/V/")

    # ── Criterion 3: R-band (20 pts) ──────────────────────────────────
    if r_count >= min_per_filter:
        score += 20
        feedback.append(f"R-band: {r_count} frames in sa98/R/")
    elif r_count >= 2:
        score += 10
        feedback.append(f"R-band: {r_count}/{min_per_filter} frames")
    elif r_count >= 1:
        score += 5
        feedback.append(f"R-band: only {r_count} frame")
    else:
        feedback.append("R-band: no frames found in sa98/R/")

    # ── Criterion 4: Telescope at SA 98 (20 pts) ──────────────────────
    coord_ok = False
    try:
        final_ra = float(result.get('final_ra', -1))
        final_dec = float(result.get('final_dec', -999))
    except (ValueError, TypeError):
        final_ra, final_dec = -1.0, -999.0

    if final_ra > 0 and final_dec > -900:
        sep_deg = angular_separation_deg(final_ra, final_dec, SA98_RA, SA98_DEC)
        sep_arcmin = sep_deg * 60.0
        if sep_arcmin <= COORD_TOL_ARCMIN:
            score += 20
            coord_ok = True
            feedback.append(f"telescope at SA 98 (sep {sep_arcmin:.1f}')")
        elif sep_arcmin <= COORD_TOL_ARCMIN * 2:
            score += 8
            feedback.append(f"telescope near SA 98 (sep {sep_arcmin:.1f}')")
        else:
            feedback.append(f"telescope NOT at SA 98 (sep {sep_arcmin:.1f}')")
    else:
        feedback.append("could not read telescope coordinates")

    # ── Criterion 5: Calibration catalog (20 pts) ─────────────────────
    catalog_exists = result.get('catalog_exists', False)
    catalog_mtime = result.get('catalog_mtime', 0)
    catalog_b64 = result.get('catalog_b64', '')

    if catalog_exists and catalog_mtime > task_start:
        if catalog_b64:
            try:
                catalog_text = base64.b64decode(catalog_b64).decode('utf-8', errors='ignore')
                catalog_text = catalog_text.replace('\\n', '\n')
                upper = catalog_text.upper()

                has_b = ' B ' in catalog_text or '\nB ' in catalog_text or 'B\t' in catalog_text
                has_v = ' V ' in catalog_text or '\nV ' in catalog_text or 'V\t' in catalog_text
                has_r = ' R ' in catalog_text or '\nR ' in catalog_text or 'R\t' in catalog_text
                has_numbers = any(c.isdigit() for c in catalog_text)

                filter_count = sum([has_b, has_v, has_r])
                if has_numbers and filter_count >= 3:
                    score += 20
                    feedback.append("calibration catalog valid (all 3 filters)")
                elif has_numbers and filter_count >= 2:
                    score += 13
                    feedback.append(f"catalog partial ({filter_count}/3 filters)")
                elif has_numbers:
                    score += 7
                    feedback.append("catalog exists but missing filter entries")
                else:
                    score += 3
                    feedback.append("catalog exists but has no data")
            except Exception as e:
                score += 3
                feedback.append(f"catalog unreadable: {e}")
        else:
            score += 3
            feedback.append("catalog file is empty")
    elif catalog_exists:
        feedback.append("catalog has pre-task timestamp")
    else:
        feedback.append("calibration catalog not found")

    # ── Final verdict ─────────────────────────────────────────────────
    # Require ALL 3 filter sets complete (not just 2) — prevents Anti-Pattern 4
    # where B(20)+V(20)+coords(20)=60 could pass without R filter set.
    filters_ok = (b_count >= min_per_filter and
                  v_count >= min_per_filter and
                  r_count >= min_per_filter)
    passed = (score >= 60) and coord_ok and filters_ok

    return {
        "passed": passed,
        "score": score,
        "feedback": "; ".join(feedback)
    }
