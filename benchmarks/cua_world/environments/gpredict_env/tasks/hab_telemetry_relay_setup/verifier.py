#!/usr/bin/env python3
"""
Verifier for hab_telemetry_relay_setup task.

Task Requirements:
1. Delete L_Band_Test module
2. Add Launch_Site QTH (34.4735 N, 104.2447 W, 1229 m)
3. Add Recovery_Team QTH (35.2220 N, 101.8313 W, 1099 m)
4. Create HAB_Relays module tracking: 25544, 27607, 40967, 43017
5. Assign HAB_Relays to use the Launch_Site QTH
6. Configure Imperial units (miles/feet)

Scoring System (100 pts total):
- L_Band_Test deleted: 10 pts
- Launch_Site QTH valid: 20 pts
- Recovery_Team QTH valid: 20 pts
- HAB_Relays satellites present: 20 pts (5 pts per sat)
- HAB_Relays QTH assigned to Launch_Site: 20 pts
- Imperial units enabled: 10 pts

Pass threshold: 70 points
"""

import json
import os
import tempfile
import logging

logger = logging.getLogger(__name__)


def _close_enough(value_str, expected_float, tolerance=0.1):
    """Check if parsed string is within tolerance of target float."""
    try:
        val = float(value_str)
        return abs(val - expected_float) <= tolerance
    except (ValueError, TypeError):
        return False


def verify_hab_telemetry_relay_setup(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env function unavailable"}

    metadata = task_info.get('metadata', {})
    
    try:
        temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        temp_path = temp_file.name
        temp_file.close()

        copy_from_env("/tmp/hab_telemetry_result.json", temp_path)
        with open(temp_path, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Result file retrieval/parsing failed: {e}"}
    finally:
        if os.path.exists(temp_path):
            os.unlink(temp_path)

    score = 0
    feedback_parts = []

    # 1. Check if L_Band_Test was deleted (10 pts)
    if not result.get('l_band_exists', True):
        score += 10
        feedback_parts.append("L_Band_Test module successfully deleted")
    else:
        feedback_parts.append("L_Band_Test module was NOT deleted")

    # 2. Check Launch Site QTH (20 pts)
    launch_exists = result.get('launch_site_exists', False)
    launch_filename = result.get('launch_site_filename', '')
    if launch_exists:
        lat_ok = _close_enough(result.get('launch_site_lat', ''), metadata.get('launch_site_lat', 34.4735))
        lon_ok = _close_enough(result.get('launch_site_lon', ''), metadata.get('launch_site_lon', -104.2447))
        alt_ok = _close_enough(result.get('launch_site_alt', ''), metadata.get('launch_site_alt', 1229), tolerance=20)
        
        if lat_ok and lon_ok and alt_ok:
            score += 20
            feedback_parts.append("Launch_Site ground station: correct coordinates")
        elif lat_ok and lon_ok:
            score += 12
            feedback_parts.append("Launch_Site ground station: coordinates correct but altitude wrong")
        else:
            score += 5
            feedback_parts.append("Launch_Site ground station: found but coordinates inaccurate")
    else:
        feedback_parts.append("Launch_Site ground station: NOT FOUND")

    # 3. Check Recovery Team QTH (20 pts)
    recovery_exists = result.get('recovery_team_exists', False)
    if recovery_exists:
        lat_ok = _close_enough(result.get('recovery_team_lat', ''), metadata.get('recovery_team_lat', 35.2220))
        lon_ok = _close_enough(result.get('recovery_team_lon', ''), metadata.get('recovery_team_lon', -101.8313))
        alt_ok = _close_enough(result.get('recovery_team_alt', ''), metadata.get('recovery_team_alt', 1099), tolerance=20)
        
        if lat_ok and lon_ok and alt_ok:
            score += 20
            feedback_parts.append("Recovery_Team ground station: correct coordinates")
        elif lat_ok and lon_ok:
            score += 12
            feedback_parts.append("Recovery_Team ground station: coordinates correct but altitude wrong")
        else:
            score += 5
            feedback_parts.append("Recovery_Team ground station: found but coordinates inaccurate")
    else:
        feedback_parts.append("Recovery_Team ground station: NOT FOUND")

    # 4. Check HAB_Relays Module Satellites (20 pts)
    hab_exists = result.get('hab_mod_exists', False)
    if hab_exists:
        sats_str = result.get('hab_satellites', '')
        sat_names = metadata.get('satellite_names', {})
        req_sats = metadata.get('required_satellites', [])
        
        found_sats = []
        for sat in req_sats:
            if str(sat) in sats_str:
                score += 5
                found_sats.append(sat_names.get(str(sat), str(sat)))
        
        if len(found_sats) == len(req_sats):
            feedback_parts.append("HAB_Relays module: contains all required satellites")
        else:
            feedback_parts.append(f"HAB_Relays module: missing some satellites. Found: {', '.join(found_sats)}")
    else:
        feedback_parts.append("HAB_Relays module: NOT FOUND")

    # 5. Check HAB_Relays Module QTH Binding (20 pts)
    if hab_exists and launch_exists and launch_filename:
        mod_qthfile = result.get('hab_qthfile', '').lower()
        # Ensure it matches the created Launch Site QTH filename
        if mod_qthfile == launch_filename.lower():
            score += 20
            feedback_parts.append("HAB_Relays module successfully bound to Launch Site QTH")
        else:
            feedback_parts.append(f"HAB_Relays module bound to wrong QTH ({mod_qthfile} instead of {launch_filename})")
    elif hab_exists:
        feedback_parts.append("HAB_Relays module QTH binding failed (Launch_Site QTH missing or unassigned)")

    # 6. Check Imperial units configuration (10 pts)
    # In GPredict: unit=0 is Metric, unit=1 is Imperial, unit=2 is Imperial/Nautical
    unit_val = result.get('unit_val', '0')
    if unit_val in ['1', '2']:
        score += 10
        feedback_parts.append("Imperial units successfully enabled")
    else:
        feedback_parts.append("Units are NOT set to Imperial")

    # Final verdict
    passed = score >= 70

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }