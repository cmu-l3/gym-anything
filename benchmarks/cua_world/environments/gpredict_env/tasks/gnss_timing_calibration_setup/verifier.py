#!/usr/bin/env python3
"""
Verifier for gnss_timing_calibration_setup task.

Task: Configure GPredict for GNSS Timing Lab Calibration:
  1. Add CelesTrak GNSS TLE feed (gnss.txt)
  2. Execute Network TLE Update (verifiable by appearance of new satdata files)
  3. Add NIST_Boulder ground station (39.9936 N, 105.2618 W, 1655 m)
  4. Assign NIST_Boulder as Default QTH
  5. Create GNSS_Timing.mod with 55268, 48859, 43058, 43565
  6. Enforce UTC Time Display (TIME_LOCAL=false)

Scoring (100 points, pass >= 70):
  - TLE URL Configured (gnss.txt in config): 10 pts
  - TLE Network Update Executed (satdata present): 15 pts
  - NIST_Boulder Created (correct coords): 15 pts
  - NIST_Boulder Set as Default QTH: 10 pts
  - GNSS_Timing Module Built (10 pts per correct sat): 40 pts
  - UTC Time Enforced: 10 pts
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


def verify_gnss_timing_calibration_setup(traj, env_info, task_info):
    """
    Verify the GNSS timing calibration setup task.

    Scoring (100 points):
    - TLE URL Configured: 10 pts
    - TLE Network Update Executed: 15 pts
    - NIST_Boulder Created: 15 pts
    - NIST_Boulder Set as Default QTH: 10 pts
    - GNSS_Timing Module Built (4 sats x 10): 40 pts
    - UTC Time Enforced: 10 pts

    Pass threshold: 70 points
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
            copy_from_env("/tmp/gnss_timing_calibration_setup_result.json", temp_path)
        except Exception as e:
            return {"passed": False, "score": 0,
                    "feedback": f"Could not copy result file: {e}"}

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

    # --- Criterion 1: TLE URL Configured (10 pts) ---
    if result.get('tle_url_added', False):
        score += 10
        feedback_parts.append("GNSS TLE feed (gnss.txt) added to preferences")
    else:
        feedback_parts.append("GNSS TLE feed missing from preferences")

    # --- Criterion 2: TLE Network Update Executed (15 pts) ---
    if result.get('tle_downloaded', False):
        score += 15
        feedback_parts.append("Network update executed (GNSS sats downloaded)")
    else:
        feedback_parts.append("Network update NOT executed (GNSS sats missing from cache)")

    # --- Criterion 3: NIST_Boulder Ground Station (15 pts) ---
    nist_exists = result.get('nist_exists', False)
    if nist_exists:
        lat_ok = _close_enough(result.get('nist_lat', ''), metadata.get('nist_lat', 39.9936), 0.1)
        lon_ok = _close_enough(result.get('nist_lon', ''), metadata.get('nist_lon', -105.2618), 0.1)
        alt_ok = _close_enough(result.get('nist_alt', ''), metadata.get('nist_alt', 1655), 50)

        if lat_ok and lon_ok and alt_ok:
            score += 15
            feedback_parts.append("NIST_Boulder ground station created correctly")
        elif lat_ok and lon_ok:
            score += 10
            feedback_parts.append(f"NIST_Boulder exists but altitude incorrect ({result.get('nist_alt')}m)")
        else:
            score += 5
            feedback_parts.append(f"NIST_Boulder exists with incorrect coordinates (Lat: {result.get('nist_lat')}, Lon: {result.get('nist_lon')})")
    else:
        feedback_parts.append("NIST_Boulder ground station NOT found")

    # --- Criterion 4: Default QTH Set (10 pts) ---
    default_qth = result.get('default_qth', '').lower()
    if 'nist' in default_qth or 'boulder' in default_qth:
        score += 10
        feedback_parts.append("NIST_Boulder set as Default QTH")
    else:
        feedback_parts.append(f"Default QTH is not NIST_Boulder (currently: {default_qth})")

    # --- Criterion 5: GNSS_Timing Module Built (40 pts total) ---
    if result.get('gnss_mod_exists', False):
        sats_found = []
        sats_missing = []
        
        sat_checks = [
            ('gnss_has_55268', 55268, 'NAVSTAR 82'),
            ('gnss_has_48859', 48859, 'NAVSTAR 81'),
            ('gnss_has_43058', 43058, 'GALILEO 22'),
            ('gnss_has_43565', 43565, 'GALILEO 26')
        ]
        
        for key, norad, name in sat_checks:
            if result.get(key, False):
                score += 10
                sats_found.append(f"{name} ({norad})")
            else:
                sats_missing.append(f"{name} ({norad})")
                
        if sats_found:
            feedback_parts.append(f"GNSS module contains: {', '.join(sats_found)}")
        if sats_missing:
            feedback_parts.append(f"GNSS module MISSING: {', '.join(sats_missing)}")
    else:
        feedback_parts.append("GNSS_Timing module NOT found")

    # --- Criterion 6: UTC Time Enforced (10 pts) ---
    if result.get('utc_time_enabled', False):
        score += 10
        feedback_parts.append("UTC Time configured")
    else:
        cfg = result.get('gpredict_cfg_content', '')
        if re.search(r'TIME_LOCAL\s*=\s*false', cfg, re.IGNORECASE) or re.search(r'utc\s*=\s*1', cfg, re.IGNORECASE):
            score += 10
            feedback_parts.append("UTC Time configured (detected in raw cfg)")
        else:
            feedback_parts.append("UTC Time NOT configured (Local time still active)")

    passed = score >= 70 and result.get('tle_downloaded', False)
    
    # Require network update as a key criterion to prevent gaming
    if score >= 70 and not result.get('tle_downloaded', False):
        feedback_parts.append("FAIL: Passing score reached, but Network Update was not executed (anti-gaming)")

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }