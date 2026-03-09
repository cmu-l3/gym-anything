#!/usr/bin/env python3
"""
Verifier for space_station_constellation task.

Task: Configure GPredict for complete space station tracking:
  1. Complete SpaceStations.mod:
     - ISS ZARYA (25544) — already present
     - ISS POISK (36086) — add
     - ISS NAUKA (49044) — add
     - CSS TIANHE (48274) — add
     - CSS WENTIAN (53239) — add
     - CSS MENGTIAN (54216) — add
  2. Add JSC/Houston ground station (29.5502N, 95.0970W, 14m)
  3. Add KSC ground station (28.5729N, 80.6490W, 3m)
  4. Enable UTC time display

Scoring (100 points, pass >= 70):
  - SpaceStations module satellites (10 pts each × 6): 60 pts total
  - JSC/Houston ground station: 15 pts
  - KSC ground station: 15 pts
  - UTC time enabled: 10 pts
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


def _check_utc_time(result):
    """Check if UTC time is enabled using multiple strategies."""
    if result.get('utc_time_enabled'):
        return True

    cfg_content = result.get('gpredict_cfg_content', '')
    if cfg_content:
        # Look for utc=1 in any form
        if re.search(r'utc\s*=\s*1', cfg_content):
            return True

    return False


def verify_space_station_constellation(traj, env_info, task_info):
    """
    Verify space station constellation configuration task.

    Scoring (100 points):
    SpaceStations module (10 pts each):
      - ISS ZARYA (25544): 10 pts
      - ISS POISK (36086): 10 pts
      - ISS NAUKA (49044): 10 pts
      - CSS TIANHE (48274): 10 pts
      - CSS WENTIAN (53239): 10 pts
      - CSS MENGTIAN (54216): 10 pts
    JSC/Houston ground station: 15 pts
    KSC ground station: 15 pts
    UTC time enabled: 10 pts

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
            copy_from_env("/tmp/space_station_constellation_result.json", temp_path)
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

    # --- SpaceStations module satellites (60 pts, 10 per satellite) ---
    if not result.get('spacestations_exists'):
        feedback_parts.append("CRITICAL: SpaceStations module NOT FOUND")
    else:
        satellite_checks = [
            ('ss_has_zarya', 25544, 'ISS (ZARYA)'),
            ('ss_has_poisk', 36086, 'ISS (POISK)'),
            ('ss_has_nauka', 49044, 'ISS (NAUKA)'),
            ('ss_has_tianhe', 48274, 'CSS (TIANHE)'),
            ('ss_has_wentian', 53239, 'CSS (WENTIAN)'),
            ('ss_has_mengtian', 54216, 'CSS (MENGTIAN)'),
        ]

        present_sats = []
        missing_sats = []

        for key, norad_id, name in satellite_checks:
            if result.get(key, False):
                score += 10
                present_sats.append(f"{name} ({norad_id})")
            else:
                missing_sats.append(f"{name} ({norad_id})")

        if present_sats:
            feedback_parts.append(f"SpaceStations has: {', '.join(present_sats)}")
        if missing_sats:
            feedback_parts.append(f"SpaceStations MISSING: {', '.join(missing_sats)}")

    # --- JSC/Houston ground station (15 pts) ---
    if result.get('jsc_exists'):
        lat_ok = _close_enough(result.get('jsc_lat', ''), metadata.get('jsc_lat', 29.5502), 0.15)
        lon_ok = _close_enough(result.get('jsc_lon', ''), metadata.get('jsc_lon', -95.0970), 0.15)
        alt_ok = _close_enough(result.get('jsc_alt', ''), metadata.get('jsc_alt', 14), 30)

        if lat_ok and lon_ok and alt_ok:
            score += 15
            feedback_parts.append("JSC/Houston ground station: correct")
        elif lat_ok and lon_ok:
            score += 10
            feedback_parts.append(f"JSC/Houston: coordinates OK but altitude off ({result.get('jsc_alt')}m, expected 14m)")
        else:
            score += 5
            feedback_parts.append(f"JSC/Houston exists but coordinates wrong (lat={result.get('jsc_lat')}, lon={result.get('jsc_lon')})")
    else:
        feedback_parts.append("JSC/Houston ground station: NOT FOUND (no .qth near 29.5N, 95.1W)")

    # --- KSC ground station (15 pts) ---
    if result.get('ksc_exists'):
        lat_ok = _close_enough(result.get('ksc_lat', ''), metadata.get('ksc_lat', 28.5729), 0.15)
        lon_ok = _close_enough(result.get('ksc_lon', ''), metadata.get('ksc_lon', -80.6490), 0.15)
        alt_ok = _close_enough(result.get('ksc_alt', ''), metadata.get('ksc_alt', 3), 20)

        if lat_ok and lon_ok and alt_ok:
            score += 15
            feedback_parts.append("Kennedy Space Center ground station: correct")
        elif lat_ok and lon_ok:
            score += 10
            feedback_parts.append(f"KSC: coordinates OK but altitude off ({result.get('ksc_alt')}m, expected 3m)")
        else:
            score += 5
            feedback_parts.append(f"KSC exists but coordinates wrong (lat={result.get('ksc_lat')}, lon={result.get('ksc_lon')})")
    else:
        feedback_parts.append("KSC ground station: NOT FOUND (no .qth near 28.6N, 80.6W)")

    # --- UTC time (10 pts) ---
    if _check_utc_time(result):
        score += 10
        feedback_parts.append("UTC time: enabled")
    else:
        feedback_parts.append("UTC time: NOT enabled (check Edit > Preferences > Time)")

    passed = score >= 70
    all_sats_present = all([
        result.get('ss_has_zarya'), result.get('ss_has_poisk'), result.get('ss_has_nauka'),
        result.get('ss_has_tianhe'), result.get('ss_has_wentian'), result.get('ss_has_mengtian')
    ])

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts),
        "subscores": {
            "spacestations_complete": all_sats_present,
            "jsc_station": result.get('jsc_exists'),
            "ksc_station": result.get('ksc_exists'),
            "utc_time": _check_utc_time(result),
        }
    }
