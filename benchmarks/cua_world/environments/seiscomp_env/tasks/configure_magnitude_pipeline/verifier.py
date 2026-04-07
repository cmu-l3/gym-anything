#!/usr/bin/env python3
"""
Verifier for configure_magnitude_pipeline task.

This uses a highly robust mechanism: instead of attempting to parse the user's
arbitrary `scamp.cfg` and `scmag.cfg` files (which support nested blocks, aliases, etc.),
the export script commands SeisComP to dump the parsed, flattened configuration.
We then strictly verify these dumped, effective configurations.
"""

import os
import sys
import json
import base64
import re
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def get_flat_val(text, key):
    """
    Search a flattened SeisComP config dump for a specific key.
    Handles 'key = value' lines.
    """
    # Look for start of line, optional whitespace, key name, optional whitespace, =, value
    pattern = rf'^\s*{re.escape(key)}\s*=\s*(.+)$'
    match = re.search(pattern, text, re.MULTILINE)
    if match:
        # Strip trailing whitespace and wrapping quotes
        return match.group(1).strip().strip('"\'')
    return None


def clean_format(val):
    """Remove spaces for robust comparison (e.g. BW(3, 0.5, 12.0) -> BW(3,0.5,12.0))"""
    if val is None:
        return ""
    # Remove all whitespace
    val = re.sub(r'\s+', '', str(val))
    # Standardize floating points ending in .0
    val = re.sub(r'\.0([^0-9]|$)', r'\1', val)
    return val


def verify_magnitude_pipeline(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load result exported from container
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read exported results: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback_parts = []
    task_start = result.get('task_start', 0)

    # 1. Parse scamp parameters
    scamp_mtime = result.get('scamp_mtime', 0)
    true_scamp_text = base64.b64decode(result.get('true_scamp_b64', '')).decode('utf-8', errors='ignore')

    if scamp_mtime >= task_start and scamp_mtime > 0:
        score += 5
        feedback_parts.append("scamp.cfg created/modified (+5)")
    else:
        feedback_parts.append("scamp.cfg not modified during task")

    # Scamp ML settings
    ml_filter = get_flat_val(true_scamp_text, "amplitudes.ML.filter")
    if clean_format(ml_filter) in ["BW(3,0.5,12)", "BW(3,0.5,12.0)"]:
        score += 10
        feedback_parts.append("ML filter correct (+10)")
    else:
        feedback_parts.append(f"ML filter mismatch (got {ml_filter})")

    ml_minsnr = get_flat_val(true_scamp_text, "amplitudes.ML.minSNR")
    if clean_format(ml_minsnr) == "3":
        score += 8
        feedback_parts.append("ML minSNR correct (+8)")
    else:
        feedback_parts.append(f"ML minSNR mismatch (got {ml_minsnr})")

    ml_mindist = get_flat_val(true_scamp_text, "amplitudes.ML.minDist")
    ml_maxdist = get_flat_val(true_scamp_text, "amplitudes.ML.maxDist")
    dist_pts = 0
    if clean_format(ml_mindist) == "0": dist_pts += 3
    if clean_format(ml_maxdist) == "8": dist_pts += 4
    if dist_pts == 7:
        score += 7
        feedback_parts.append("ML distances correct (+7)")
    else:
        score += dist_pts
        feedback_parts.append(f"ML distances partial/incorrect (+{dist_pts})")

    # Scamp mb settings
    mb_filter = get_flat_val(true_scamp_text, "amplitudes.mb.filter")
    if clean_format(mb_filter) in ["BW(3,0.7,2)", "BW(3,0.7,2.0)"]:
        score += 10
        feedback_parts.append("mb filter correct (+10)")
    else:
        feedback_parts.append(f"mb filter mismatch (got {mb_filter})")

    mb_mindist = get_flat_val(true_scamp_text, "amplitudes.mb.minDist")
    mb_maxdist = get_flat_val(true_scamp_text, "amplitudes.mb.maxDist")
    dist_pts_mb = 0
    if clean_format(mb_mindist) == "5": dist_pts_mb += 3
    if clean_format(mb_maxdist) == "105": dist_pts_mb += 4
    if dist_pts_mb == 7:
        score += 7
        feedback_parts.append("mb distances correct (+7)")
    else:
        score += dist_pts_mb
        feedback_parts.append(f"mb distances partial/incorrect (+{dist_pts_mb})")

    # 2. Parse scmag parameters
    scmag_mtime = result.get('scmag_mtime', 0)
    true_scmag_text = base64.b64decode(result.get('true_scmag_b64', '')).decode('utf-8', errors='ignore')

    if scmag_mtime >= task_start and scmag_mtime > 0:
        score += 5
        feedback_parts.append("scmag.cfg created/modified (+5)")
    else:
        feedback_parts.append("scmag.cfg not modified during task")

    # Scmag ML settings
    scmag_ml_sta = get_flat_val(true_scmag_text, "magnitudes.ML.minStationCount")
    if clean_format(scmag_ml_sta) == "3":
        score += 8
        feedback_parts.append("ML minStationCount correct (+8)")
    else:
        feedback_parts.append(f"ML minStationCount mismatch (got {scmag_ml_sta})")

    scmag_ml_min = get_flat_val(true_scmag_text, "magnitudes.ML.minDist")
    scmag_ml_max = get_flat_val(true_scmag_text, "magnitudes.ML.maxDist")
    scmag_ml_pts = 0
    if clean_format(scmag_ml_min) == "0": scmag_ml_pts += 2
    if clean_format(scmag_ml_max) == "8": scmag_ml_pts += 3
    if scmag_ml_pts == 5:
        score += 5
        feedback_parts.append("scmag ML distances correct (+5)")
    else:
        score += scmag_ml_pts
        feedback_parts.append(f"scmag ML distances partial (+{scmag_ml_pts})")

    # Scmag mb settings
    scmag_mb_sta = get_flat_val(true_scmag_text, "magnitudes.mb.minStationCount")
    if clean_format(scmag_mb_sta) == "4":
        score += 8
        feedback_parts.append("mb minStationCount correct (+8)")
    else:
        feedback_parts.append(f"mb minStationCount mismatch (got {scmag_mb_sta})")

    scmag_mb_min = get_flat_val(true_scmag_text, "magnitudes.mb.minDist")
    scmag_mb_max = get_flat_val(true_scmag_text, "magnitudes.mb.maxDist")
    scmag_mb_pts = 0
    if clean_format(scmag_mb_min) == "5": scmag_mb_pts += 2
    if clean_format(scmag_mb_max) == "105": scmag_mb_pts += 3
    if scmag_mb_pts == 5:
        score += 5
        feedback_parts.append("scmag mb distances correct (+5)")
    else:
        score += scmag_mb_pts
        feedback_parts.append(f"scmag mb distances partial (+{scmag_mb_pts})")

    # Scmag whitelist check
    whitelist_raw = get_flat_val(true_scmag_text, "magnitudes.whitelist") or \
                    get_flat_val(true_scmag_text, "magnitudes.types") or \
                    get_flat_val(true_scmag_text, "magnitudes") or ""
    
    wl_found = [x.strip() for x in whitelist_raw.split(',') if x.strip()]
    req_types = ["ML", "mb", "mB", "Mw(mB)"]
    matched = [t for t in req_types if any(clean_format(t).lower() == clean_format(x).lower() for x in wl_found)]
    
    if len(matched) == 4:
        score += 7
        feedback_parts.append("Magnitude whitelist correct (+7)")
    else:
        feedback_parts.append(f"Magnitude whitelist missing items. Expected {req_types}, got {wl_found}")

    # 3. Check dump file commands
    user_scamp_size = result.get('user_scamp_dump_size', 0)
    if user_scamp_size > 100:
        score += 7
        feedback_parts.append("scamp config dumped by user (+7)")
    else:
        feedback_parts.append("User scamp dump file empty or missing")

    user_scmag_size = result.get('user_scmag_dump_size', 0)
    if user_scmag_size > 100:
        score += 8
        feedback_parts.append("scmag config dumped by user (+8)")
    else:
        feedback_parts.append("User scmag dump file empty or missing")

    # Compute final threshold
    passed = score >= 60

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }