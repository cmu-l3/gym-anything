#!/usr/bin/env python3
"""
Verifier for marine_argos_tracking_setup task.

Task: Configure GPredict for a marine biology expedition.
  1. Delete Amateur.mod
  2. Create Argos_Tracking.mod with 5 Argos satellites
  3. Create Galapagos ground station (-0.7402, -90.3138, 15m)
  4. Create Ascension ground station (-7.9467, -14.3559, 10m)
  5. Bind Galapagos directly to the Argos_Tracking module
  6. Configure Argos_Tracking layout to list-only views (no maps)
  7. Enable metric units globally

Scoring (100 points, pass >= 70):
  - Default module deleted: 10 pts
  - Argos module created: 10 pts
  - Argos satellites added: 25 pts (5 pts per sat)
  - Galapagos Station correct: 15 pts
  - Ascension Station correct: 15 pts
  - Module QTH bound to Galapagos: 10 pts
  - Module Layout is list-only: 10 pts
  - Metric units enabled: 5 pts
"""

import json
import os
import tempfile
import logging

logger = logging.getLogger(__name__)

def _close_enough(value_str, expected_float, tolerance=0.1):
    try:
        if not value_str:
            return False
        val = float(value_str)
        return abs(val - expected_float) <= tolerance
    except (ValueError, TypeError):
        return False

def verify_marine_argos_tracking(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env unavailable"}

    metadata = task_info.get('metadata', {})
    
    try:
        temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        temp_path = temp_file.name
        temp_file.close()

        try:
            copy_from_env("/tmp/marine_argos_tracking_result.json", temp_path)
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

    # 1. Default Module Deleted (10 pts)
    if not result.get('amateur_exists', True):
        score += 10
        feedback_parts.append("Amateur module successfully deleted")
    else:
        feedback_parts.append("Amateur module still exists")

    # 2. Argos Module Created (10 pts)
    argos_exists = result.get('argos_exists', False)
    if argos_exists:
        score += 10
        feedback_parts.append("Argos_Tracking module created")
    else:
        feedback_parts.append("Argos_Tracking module NOT FOUND")

    # 3. Satellites Added (25 pts)
    if argos_exists:
        sat_str = result.get('argos_satellites', '')
        sats = metadata.get('argos_satellites', [25338, 28654, 33591, 38771, 43689])
        sats_found = 0
        for sat in sats:
            if str(sat) in sat_str:
                sats_found += 1
        
        score += (sats_found * 5)
        feedback_parts.append(f"Argos satellites: {sats_found}/5 added")

    # 4. Galapagos Station (15 pts)
    if result.get('galapagos_exists'):
        lat_ok = _close_enough(result.get('galapagos_lat', ''), metadata.get('galapagos_lat', -0.7402), 0.1)
        lon_ok = _close_enough(result.get('galapagos_lon', ''), metadata.get('galapagos_lon', -90.3138), 0.1)
        alt_ok = _close_enough(result.get('galapagos_alt', ''), metadata.get('galapagos_alt', 15), 10)
        
        if lat_ok and lon_ok and alt_ok:
            score += 15
            feedback_parts.append("Galapagos ground station: correct")
        elif lat_ok and lon_ok:
            score += 10
            feedback_parts.append("Galapagos ground station: coordinates OK, altitude incorrect")
        else:
            score += 5
            feedback_parts.append("Galapagos ground station: found but coordinates wrong")
    else:
        feedback_parts.append("Galapagos ground station: NOT FOUND")

    # 5. Ascension Station (15 pts)
    if result.get('ascension_exists'):
        lat_ok = _close_enough(result.get('ascension_lat', ''), metadata.get('ascension_lat', -7.9467), 0.1)
        lon_ok = _close_enough(result.get('ascension_lon', ''), metadata.get('ascension_lon', -14.3559), 0.1)
        alt_ok = _close_enough(result.get('ascension_alt', ''), metadata.get('ascension_alt', 10), 10)
        
        if lat_ok and lon_ok and alt_ok:
            score += 15
            feedback_parts.append("Ascension ground station: correct")
        elif lat_ok and lon_ok:
            score += 10
            feedback_parts.append("Ascension ground station: coordinates OK, altitude incorrect")
        else:
            score += 5
            feedback_parts.append("Ascension ground station: found but coordinates wrong")
    else:
        feedback_parts.append("Ascension ground station: NOT FOUND")

    # 6. Module QTH Binding (10 pts)
    if argos_exists:
        qthfile = result.get('argos_qthfile', '').lower()
        if 'galapagos' in qthfile:
            score += 10
            feedback_parts.append("Argos module properly bound to Galapagos station")
        else:
            feedback_parts.append(f"Argos module bound to '{qthfile}', expected Galapagos")

    # 7. Module Layout (10 pts)
    if argos_exists:
        layout = result.get('argos_layout', '')
        showmap = result.get('argos_showmap', '')
        showpolar = result.get('argos_showpolarplot', '')
        
        list_only = False
        if showmap == '0' and showpolar == '0':
            list_only = True
        elif layout and layout not in ['0', '1', '2', '3']:
            list_only = True
            
        if list_only:
            score += 10
            feedback_parts.append("Argos module layout configured to list-only views")
        else:
            feedback_parts.append("Argos module layout still contains maps or polar plots")

    # 8. Metric Units (5 pts)
    if result.get('metric_units_enabled'):
        score += 5
        feedback_parts.append("Metric units enabled")
    else:
        feedback_parts.append("Metric units NOT enabled")

    passed = score >= 70
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }