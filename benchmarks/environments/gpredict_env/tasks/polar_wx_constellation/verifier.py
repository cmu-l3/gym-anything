#!/usr/bin/env python3
"""
Verifier for polar_wx_constellation task.

Task: Configure GPredict for polar-orbiting weather satellite tracking:
  1. Fix PolarWX module: remove ISS (25544), add 4 weather satellites
     (SUOMI NPP 37849, FENGYUN 3A 32958, FENGYUN 3B 37214, DMSP F18 35951)
  2. Add Fairbanks AK ground station (64.8378N, 147.7164W, 133m)
  3. Add Anchorage AK ground station (61.2181N, 149.9003W, 38m)
  4. Enable metric units in preferences

Scoring (100 points, pass >= 70):
  - PolarWX module has all 4 weather satellites:      25 pts
  - PolarWX module does NOT contain ISS:               5 pts
  - Fairbanks AK ground station correct:              20 pts
  - Anchorage AK ground station correct:              20 pts
  - Metric units enabled:                             15 pts
  - Partial credit for 3/4 weather sats:             graduated
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


def _check_metric_units(result):
    """Check if metric units are enabled using multiple strategies."""
    # Direct flag from export script
    if result.get('metric_units_enabled'):
        return True

    # Fallback: search raw gpredict.cfg content
    cfg_content = result.get('gpredict_cfg_content', '')
    if cfg_content:
        # Look for unit=0 in any form (GPredict stores metric as 0)
        if re.search(r'unit\s*=\s*0', cfg_content):
            return True
        # Some versions may use 'km' keyword
        if re.search(r'unit.*km|km.*unit', cfg_content, re.IGNORECASE):
            return True

    return False


def verify_polar_wx_constellation(traj, env_info, task_info):
    """
    Verify the polar weather satellite constellation configuration task.

    Scoring (100 points):
    - PolarWX has all 4 weather satellites: 25 pts
    - PolarWX does NOT have ISS: 5 pts
    - Fairbanks AK ground station: 20 pts
    - Anchorage AK ground station: 20 pts
    - Metric units enabled: 15 pts
    - Partial: 3/4 weather sats = 15 pts, 2/4 = 8 pts

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
            copy_from_env("/tmp/polar_wx_constellation_result.json", temp_path)
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

    # --- Criterion 1: PolarWX module has correct weather satellites (25 pts) ---
    if result.get('polarwx_exists'):
        has_suomi = result.get('polarwx_has_suomi_npp', False)
        has_fy3a = result.get('polarwx_has_fy3a', False)
        has_fy3b = result.get('polarwx_has_fy3b', False)
        has_dmsp = result.get('polarwx_has_dmsp_f18', False)

        wx_count = sum([has_suomi, has_fy3a, has_fy3b, has_dmsp])

        if wx_count == 4:
            score += 25
            feedback_parts.append("PolarWX module: all 4 weather satellites present")
        elif wx_count == 3:
            score += 15
            missing = []
            if not has_suomi: missing.append("SUOMI NPP (37849)")
            if not has_fy3a: missing.append("FENGYUN 3A (32958)")
            if not has_fy3b: missing.append("FENGYUN 3B (37214)")
            if not has_dmsp: missing.append("DMSP F18 (35951)")
            feedback_parts.append(f"PolarWX module: 3/4 weather sats, missing: {', '.join(missing)}")
        elif wx_count == 2:
            score += 8
            feedback_parts.append(f"PolarWX module: only 2/4 weather satellites")
        elif wx_count == 1:
            score += 3
            feedback_parts.append(f"PolarWX module: only 1/4 weather satellites")
        else:
            feedback_parts.append("PolarWX module exists but has none of the required weather satellites")
    else:
        feedback_parts.append("PolarWX module: NOT FOUND (no .mod file matching 'polar' or 'weather')")

    # --- Criterion 2: ISS removed from PolarWX (5 pts) ---
    if result.get('polarwx_exists'):
        if not result.get('polarwx_has_iss', True):
            score += 5
            feedback_parts.append("ISS correctly removed from PolarWX module")
        else:
            feedback_parts.append("ISS (25544) still present in PolarWX — should be removed")

    # --- Criterion 3: Fairbanks AK ground station (20 pts) ---
    if result.get('fairbanks_exists'):
        lat_ok = _close_enough(result.get('fairbanks_lat', ''), metadata.get('fairbanks_lat', 64.8378), 0.1)
        lon_ok = _close_enough(result.get('fairbanks_lon', ''), metadata.get('fairbanks_lon', -147.7164), 0.1)
        alt_ok = _close_enough(result.get('fairbanks_alt', ''), metadata.get('fairbanks_alt', 133), 20)

        if lat_ok and lon_ok and alt_ok:
            score += 20
            feedback_parts.append("Fairbanks AK ground station: correct")
        elif lat_ok and lon_ok:
            score += 12
            feedback_parts.append(f"Fairbanks AK: coordinates OK but altitude off ({result.get('fairbanks_alt')}m, expected 133m)")
        else:
            score += 5
            feedback_parts.append(f"Fairbanks AK exists but coordinates wrong (lat={result.get('fairbanks_lat')})")
    else:
        feedback_parts.append("Fairbanks AK ground station: NOT FOUND (no .qth with lat starting 64)")

    # --- Criterion 4: Anchorage AK ground station (20 pts) ---
    if result.get('anchorage_exists'):
        lat_ok = _close_enough(result.get('anchorage_lat', ''), metadata.get('anchorage_lat', 61.2181), 0.1)
        lon_ok = _close_enough(result.get('anchorage_lon', ''), metadata.get('anchorage_lon', -149.9003), 0.1)
        alt_ok = _close_enough(result.get('anchorage_alt', ''), metadata.get('anchorage_alt', 38), 20)

        if lat_ok and lon_ok and alt_ok:
            score += 20
            feedback_parts.append("Anchorage AK ground station: correct")
        elif lat_ok and lon_ok:
            score += 12
            feedback_parts.append(f"Anchorage AK: coordinates OK but altitude off ({result.get('anchorage_alt')}m, expected 38m)")
        else:
            score += 5
            feedback_parts.append(f"Anchorage AK exists but coordinates wrong (lat={result.get('anchorage_lat')})")
    else:
        feedback_parts.append("Anchorage AK ground station: NOT FOUND (no .qth with lat starting 61)")

    # --- Criterion 5: Metric units (15 pts) ---
    if _check_metric_units(result):
        score += 15
        feedback_parts.append("Metric units: enabled")
    else:
        feedback_parts.append("Metric units: NOT enabled (check Edit > Preferences > Units)")

    passed = score >= 70

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts),
        "subscores": {
            "polarwx_weather_sats": result.get('polarwx_has_suomi_npp') and result.get('polarwx_has_fy3a') and result.get('polarwx_has_fy3b') and result.get('polarwx_has_dmsp_f18'),
            "iss_removed": result.get('polarwx_exists') and not result.get('polarwx_has_iss'),
            "fairbanks_station": result.get('fairbanks_exists'),
            "anchorage_station": result.get('anchorage_exists'),
            "metric_units": _check_metric_units(result),
        }
    }
