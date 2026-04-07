#!/usr/bin/env python3
"""
Verifier for poes_downlink_schedule_setup task.

Task: Bring GPredict's POES_Tracking module to operational status:
  1. Correct Wallops_CDA ground station (lat, lon direction, WX code)
  2. Set Wallops_CDA as default ground station
  3. Remove wrong satellites (ISS, Hubble, GPS) from POES_Tracking module
  4. Add correct POES fleet (NOAA-15/18/19, METOP-B/C, SUOMI NPP)
  5. Bind module to Wallops_CDA
  6. Configure Map+Table layout with topo map, terminator, specific columns
  7. Set UTC time and Metric units
  8. Export METOP-C pass predictions to ~/Documents/METOP_C_passes.txt

Scoring (100 points, pass >= 65):
  - Wallops latitude corrected:             10 pts
  - Wallops longitude corrected (West):      8 pts
  - Wallops WX code corrected:               4 pts
  - Wallops_CDA set as default QTH:          5 pts
  - Wrong satellites removed from module:     8 pts
  - NOAA-15/18/19 added:                     8 pts
  - METOP-B/C added:                         7 pts
  - SUOMI NPP added:                         5 pts
  - Module bound to Wallops_CDA:             5 pts
  - Map+Table layout configured:             5 pts  (stub — VLM verification recommended)
  - Topo map background:                     5 pts  (stub — VLM verification recommended)
  - Terminator line enabled:                 5 pts  (stub — VLM verification recommended)
  - Table columns configured:               5 pts  (stub — VLM verification recommended)
  - UTC time display:                        5 pts
  - Metric units:                            5 pts
  - Pass prediction file exported:          10 pts
"""

import json
import os
import tempfile
import logging

logger = logging.getLogger(__name__)


def _close_enough(value_str, expected_float, tolerance=0.15):
    """Check if a string-encoded float is within tolerance of expected."""
    try:
        val = float(value_str)
        return abs(val - expected_float) <= tolerance
    except (ValueError, TypeError):
        return False


def verify_poes_downlink_schedule_setup(traj, env_info, task_info):
    """
    Verify the POES downlink schedule setup task.

    Pass threshold: 65 points
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env unavailable"}

    metadata = task_info.get('metadata', {})

    # Copy result file from environment
    try:
        temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        temp_path = temp_file.name
        temp_file.close()

        try:
            copy_from_env("/tmp/poes_downlink_schedule_setup_result.json", temp_path)
        except Exception as e:
            return {"passed": False, "score": 0,
                    "feedback": f"Could not copy result file: {e}. Was the export script run?"}

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

    # --- 1. Wallops latitude corrected (10 pts) ---
    correct_lat = metadata.get('wallops_correct_lat', 37.9402)
    wallops_lat = result.get('wallops_lat', '')
    if _close_enough(wallops_lat, correct_lat, 0.15):
        score += 10
        feedback_parts.append("Wallops latitude: CORRECT")
    else:
        feedback_parts.append(f"Wallops latitude: {wallops_lat} (expected ~{correct_lat})")

    # --- 2. Wallops longitude corrected — must be negative/West (8 pts) ---
    correct_lon = metadata.get('wallops_correct_lon', -75.4576)
    wallops_lon = result.get('wallops_lon', '')
    if _close_enough(wallops_lon, correct_lon, 0.15):
        score += 8
        feedback_parts.append("Wallops longitude: CORRECT (West)")
    else:
        try:
            lon_val = float(wallops_lon)
            if lon_val > 0:
                feedback_parts.append(f"Wallops longitude: {wallops_lon} — still East (should be West/negative)")
            else:
                feedback_parts.append(f"Wallops longitude: {wallops_lon} (expected ~{correct_lon})")
        except (ValueError, TypeError):
            feedback_parts.append(f"Wallops longitude: '{wallops_lon}' (expected ~{correct_lon})")

    # --- 3. Wallops WX code (4 pts) ---
    correct_wx = metadata.get('wallops_correct_wx', 'KWAL')
    wallops_wx = result.get('wallops_wx', '').strip().upper()
    if wallops_wx == correct_wx.upper():
        score += 4
        feedback_parts.append("Wallops WX code: CORRECT")
    else:
        feedback_parts.append(f"Wallops WX code: '{wallops_wx}' (expected '{correct_wx}')")

    # --- 4. Default QTH set to Wallops_CDA (5 pts) ---
    default_qth = result.get('default_qth', '')
    if 'wallops' in default_qth.lower() or 'Wallops_CDA' in default_qth:
        score += 5
        feedback_parts.append("Default QTH: Wallops_CDA")
    else:
        feedback_parts.append(f"Default QTH: '{default_qth}' (expected Wallops_CDA)")

    # --- 5. Wrong satellites removed (8 pts) ---
    still_has_iss = result.get('poes_still_has_iss', True)
    still_has_hubble = result.get('poes_still_has_hubble', True)
    still_has_gps = result.get('poes_still_has_gps', True)
    wrong_removed = sum([not still_has_iss, not still_has_hubble, not still_has_gps])

    if wrong_removed == 3:
        score += 8
        feedback_parts.append("Wrong satellites: all 3 removed")
    elif wrong_removed > 0:
        score += 3
        remaining = []
        if still_has_iss: remaining.append("ISS")
        if still_has_hubble: remaining.append("Hubble")
        if still_has_gps: remaining.append("GPS")
        feedback_parts.append(f"Wrong satellites: {wrong_removed}/3 removed, still has: {', '.join(remaining)}")
    else:
        feedback_parts.append("Wrong satellites: none removed")

    # --- 6. NOAA-15/18/19 added (8 pts) ---
    has_n15 = result.get('poes_has_noaa15', False)
    has_n18 = result.get('poes_has_noaa18', False)
    has_n19 = result.get('poes_has_noaa19', False)
    noaa_count = sum([has_n15, has_n18, has_n19])

    if noaa_count == 3:
        score += 8
        feedback_parts.append("NOAA-15/18/19: all present")
    elif noaa_count > 0:
        score += 3
        feedback_parts.append(f"NOAA fleet: {noaa_count}/3 present")
    else:
        feedback_parts.append("NOAA-15/18/19: none added")

    # --- 7. METOP-B/C added (7 pts) ---
    has_mb = result.get('poes_has_metopb', False)
    has_mc = result.get('poes_has_metopc', False)
    metop_count = sum([has_mb, has_mc])

    if metop_count == 2:
        score += 7
        feedback_parts.append("METOP-B/C: both present")
    elif metop_count == 1:
        score += 3
        feedback_parts.append(f"METOP: {'B' if has_mb else 'C'} present, {'C' if has_mb else 'B'} missing")
    else:
        feedback_parts.append("METOP-B/C: neither added")

    # --- 8. SUOMI NPP added (5 pts) ---
    if result.get('poes_has_suominpp', False):
        score += 5
        feedback_parts.append("SUOMI NPP: present")
    else:
        feedback_parts.append("SUOMI NPP: missing")

    # --- 9. Module bound to Wallops_CDA (5 pts) ---
    poes_qthfile = result.get('poes_qthfile', '')
    if 'wallops' in poes_qthfile.lower() or 'Wallops_CDA' in poes_qthfile:
        score += 5
        feedback_parts.append("Module binding: Wallops_CDA")
    else:
        feedback_parts.append(f"Module binding: '{poes_qthfile}' (expected Wallops_CDA)")

    # --- 10-13. Layout/map/terminator/columns (20 pts total) ---
    # These are best verified by VLM checklist. Stub scoring from .mod file keys.
    poes_grid = result.get('poes_grid', '').strip()
    poes_terminator = result.get('poes_show_terminator', '').strip().lower()
    poes_map_file = result.get('poes_map_file', '').strip().lower()

    # Layout: check if GRID suggests map+table
    if poes_grid and poes_grid not in ['0']:
        # Non-default grid was set — likely the agent configured it
        score += 5
        feedback_parts.append(f"Layout GRID set: {poes_grid}")
    else:
        feedback_parts.append("Layout: default/unconfigured")

    # Topo map
    if 'topo' in poes_map_file:
        score += 5
        feedback_parts.append("Map: topographical")
    else:
        feedback_parts.append(f"Map: '{poes_map_file}' (expected topographical)")

    # Terminator
    if poes_terminator in ['true', '1', 'yes']:
        score += 5
        feedback_parts.append("Terminator line: enabled")
    else:
        feedback_parts.append(f"Terminator: '{poes_terminator}' (expected true)")

    # Columns (stub — would need bitmask decoding)
    poes_columns = result.get('poes_columns', '').strip()
    if poes_columns and poes_columns not in ['0']:
        score += 5
        feedback_parts.append(f"List columns configured: {poes_columns}")
    else:
        feedback_parts.append("List columns: default/unconfigured")

    # --- 14. UTC time display (5 pts) ---
    # GPredict stores USE_LOCAL_TIME=true/false; UTC means USE_LOCAL_TIME=false (or absent)
    tformat = result.get('tformat_setting', '').lower().strip()
    if tformat in ['false', '']:  # false = UTC (not using local time)
        score += 5
        feedback_parts.append("Time format: UTC")
    else:
        feedback_parts.append(f"Time format: USE_LOCAL_TIME='{tformat}' (expected false for UTC)")

    # --- 15. Metric units (5 pts) ---
    # GPredict stores USE_IMPERIAL=true/false; Metric means USE_IMPERIAL=false (or absent)
    unit = result.get('unit_setting', '').lower().strip()
    if unit in ['false', '']:  # false = Metric (not using Imperial)
        score += 5
        feedback_parts.append("Units: Metric")
    else:
        feedback_parts.append(f"Units: USE_IMPERIAL='{unit}' (expected false for Metric)")

    # --- 16. Pass prediction file exported (10 pts) ---
    pass_exists = result.get('pass_file_exists', False)
    pass_size = int(result.get('pass_file_size', 0))
    pass_has_metop = result.get('pass_file_contains_metop', False)
    task_start = int(result.get('task_start_time', 0))
    pass_mtime = int(result.get('pass_file_mtime', 0))

    if pass_exists and pass_size > 50 and pass_has_metop and pass_mtime >= task_start:
        score += 10
        feedback_parts.append("Pass prediction file: exported and valid")
    elif pass_exists and pass_size > 0:
        score += 5
        feedback_parts.append(f"Pass prediction file: exists ({pass_size} bytes) but may be incomplete")
    else:
        feedback_parts.append("Pass prediction file: NOT FOUND")

    passed = score >= 65

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts),
        "subscores": {
            "wallops_lat_correct": _close_enough(wallops_lat, correct_lat, 0.15),
            "wallops_lon_correct": _close_enough(wallops_lon, correct_lon, 0.15),
            "wallops_wx_correct": wallops_wx == correct_wx.upper(),
            "default_qth_wallops": 'wallops' in default_qth.lower(),
            "wrong_sats_removed": wrong_removed == 3,
            "noaa_fleet_complete": noaa_count == 3,
            "metop_complete": metop_count == 2,
            "suomi_present": result.get('poes_has_suominpp', False),
            "module_bound_wallops": 'wallops' in poes_qthfile.lower(),
            "utc_time": tformat in ['false', ''],
            "metric_units": unit in ['false', ''],
            "pass_file_exported": pass_exists and pass_size > 50 and pass_has_metop,
        }
    }
