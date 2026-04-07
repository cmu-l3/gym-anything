#!/usr/bin/env python3
"""
Verifier for agency_collaboration_tracking task.

Task: Reorganize GPredict for an international agency:
  1. Create NASA_Assets.mod with: 25544, 49044, 37849.
  2. Create CNSA_Assets.mod with: 48274, 53239, 54216, 32958, 37214.
  3. Delete Amateur.mod.
  4. Add Geneva QTH: 46.2044 N, 6.1432 E, 375m.
  5. Add Beijing QTH: 39.9042 N, 116.4074 E, 43m.
  6. Enable UTC time display.

Scoring (100 points, pass >= 70):
  - NASA_Assets exists: 5 pts
  - NASA_Assets contents: 8 pts per sat (25544, 49044, 37849) + 3 pts if no extras = 32 pts
  - CNSA_Assets exists: 5 pts
  - CNSA_Assets contents: 5 pts per sat (48274, 53239, 54216, 32958, 37214) + 3 pts if no extras = 33 pts
  - Amateur.mod deleted: 10 pts
  - Geneva ground station correct: 10 pts
  - Beijing ground station correct: 10 pts
  - UTC time enabled: 5 pts
"""

import json
import os
import re
import tempfile
import logging

logger = logging.getLogger(__name__)


def _close_enough(value_str, expected_float, tolerance=0.1):
    try:
        val = float(value_str)
        return abs(val - expected_float) <= tolerance
    except (ValueError, TypeError):
        return False


def _parse_sats(sats_str):
    """Parse GPredict SATELLITES= value into a set of integers."""
    if not sats_str:
        return set()
    return {int(x) for x in sats_str.split(';') if x.strip().isdigit()}


def verify_agency_collaboration_tracking(traj, env_info, task_info):
    """
    Verify the agency_collaboration_tracking task.
    Returns dict: {"passed": bool, "score": int, "feedback": str}
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env unavailable"}

    metadata = task_info.get('metadata', {})

    try:
        temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        temp_path = temp_file.name
        temp_file.close()

        try:
            copy_from_env("/tmp/agency_collaboration_tracking_result.json", temp_path)
        except Exception as e:
            return {"passed": False, "score": 0, "feedback": f"Could not copy result file: {e}"}

        with open(temp_path, 'r') as f:
            result = json.load(f)

    except (json.JSONDecodeError, FileNotFoundError) as e:
        return {"passed": False, "score": 0, "feedback": f"Result file error: {e}"}
    finally:
        try:
            os.unlink(temp_path)
        except Exception:
            pass

    score = 0
    feedback_parts = []

    # --- 1. NASA_Assets (Max 32 pts) ---
    if result.get('nasa_exists'):
        score += 5
        nasa_sats = _parse_sats(result.get('nasa_satellites', ''))
        expected_nasa = [25544, 49044, 37849]
        found_count = 0

        for sat in expected_nasa:
            if sat in nasa_sats:
                score += 8
                found_count += 1
            else:
                feedback_parts.append(f"NASA_Assets missing {sat}")

        if found_count == len(expected_nasa) and len(nasa_sats) == len(expected_nasa):
            score += 3
            feedback_parts.append("NASA_Assets module perfect")
        elif len(nasa_sats) > len(expected_nasa):
            feedback_parts.append(f"NASA_Assets contains extra satellites ({len(nasa_sats)} total)")
    else:
        feedback_parts.append("NASA_Assets module NOT FOUND")

    # --- 2. CNSA_Assets (Max 33 pts) ---
    if result.get('cnsa_exists'):
        score += 5
        cnsa_sats = _parse_sats(result.get('cnsa_satellites', ''))
        expected_cnsa = [48274, 53239, 54216, 32958, 37214]
        found_count = 0

        for sat in expected_cnsa:
            if sat in cnsa_sats:
                score += 5
                found_count += 1
            else:
                feedback_parts.append(f"CNSA_Assets missing {sat}")

        if found_count == len(expected_cnsa) and len(cnsa_sats) == len(expected_cnsa):
            score += 3
            feedback_parts.append("CNSA_Assets module perfect")
        elif len(cnsa_sats) > len(expected_cnsa):
            feedback_parts.append(f"CNSA_Assets contains extra satellites ({len(cnsa_sats)} total)")
    else:
        feedback_parts.append("CNSA_Assets module NOT FOUND")

    # --- 3. Delete Amateur.mod (10 pts) ---
    if not result.get('amateur_exists', True):
        score += 10
        feedback_parts.append("Amateur module correctly deleted")
    else:
        feedback_parts.append("Amateur module was NOT deleted")

    # --- 4. Geneva Ground Station (10 pts) ---
    if result.get('geneva_exists'):
        lat_ok = _close_enough(result.get('geneva_lat', ''), 46.2044, 0.15)
        lon_ok = _close_enough(result.get('geneva_lon', ''), 6.1432, 0.15)
        alt_ok = _close_enough(result.get('geneva_alt', ''), 375, 30)

        if lat_ok and lon_ok and alt_ok:
            score += 10
            feedback_parts.append("Geneva ground station: correct")
        else:
            score += 4
            feedback_parts.append(f"Geneva coords imprecise (lat={result.get('geneva_lat')}, lon={result.get('geneva_lon')}, alt={result.get('geneva_alt')})")
    else:
        feedback_parts.append("Geneva ground station: NOT FOUND (East longitude missed?)")

    # --- 5. Beijing Ground Station (10 pts) ---
    if result.get('beijing_exists'):
        lat_ok = _close_enough(result.get('beijing_lat', ''), 39.9042, 0.15)
        lon_ok = _close_enough(result.get('beijing_lon', ''), 116.4074, 0.15)
        alt_ok = _close_enough(result.get('beijing_alt', ''), 43, 30)

        if lat_ok and lon_ok and alt_ok:
            score += 10
            feedback_parts.append("Beijing ground station: correct")
        else:
            score += 4
            feedback_parts.append(f"Beijing coords imprecise (lat={result.get('beijing_lat')}, lon={result.get('beijing_lon')}, alt={result.get('beijing_alt')})")
    else:
        feedback_parts.append("Beijing ground station: NOT FOUND (East longitude missed?)")

    # --- 6. UTC time enabled (5 pts) ---
    utc_ok = False
    if result.get('utc_time_enabled'):
        utc_ok = True
    else:
        cfg = result.get('gpredict_cfg_content', '')
        if re.search(r'utc\s*=\s*1', cfg):
            utc_ok = True

    if utc_ok:
        score += 5
        feedback_parts.append("UTC time enabled")
    else:
        feedback_parts.append("UTC time NOT enabled")

    passed = score >= 70

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }