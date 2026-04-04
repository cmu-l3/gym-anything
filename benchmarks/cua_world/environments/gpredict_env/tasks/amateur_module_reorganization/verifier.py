#!/usr/bin/env python3
"""
Verifier for amateur_module_reorganization task.

Task: Complete two incomplete amateur satellite tracking modules:
  1. Linear.mod: add FO-29 (24278) and AO-73 (39444) alongside existing AO-7 (7530)
  2. FM_Voice.mod: add SO-50 (27607), AO-85 (40967), AO-95 (43770) alongside existing AO-27 (22825)
  3. Add Remote_RX ground station (40.7484N, 74.0060W, 10m)

Scoring (100 points, pass >= 70):
  - Linear module: 10 pts per satellite (AO-7=10, FO-29=10, AO-73=10) = 30 pts total
  - FM_Voice module: 10 pts per satellite (AO-27=10, SO-50=10, AO-85=10, AO-95=10) = 40 pts total
  - Remote_RX ground station correct: 20 pts
  - Both modules exist (not deleted): 10 pts
"""

import json
import os
import tempfile
import logging

logger = logging.getLogger(__name__)


def _close_enough(value_str, expected_float, tolerance=0.05):
    try:
        val = float(value_str)
        return abs(val - expected_float) <= tolerance
    except (ValueError, TypeError):
        return False


def verify_amateur_module_reorganization(traj, env_info, task_info):
    """
    Verify amateur satellite module reorganization task.

    Scoring (100 points):
    Linear module satellites (10 pts each):
      - AO-7 (7530): 10 pts
      - FO-29 (24278): 10 pts
      - AO-73/FuncUBE-1 (39444): 10 pts
    FM_Voice module satellites (10 pts each):
      - AO-27 (22825): 10 pts
      - SO-50 (27607): 10 pts
      - AO-85 (40967): 10 pts
      - AO-95 (43770): 10 pts
    Remote_RX ground station correct: 20 pts
    Both modules exist: 10 pts

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
            copy_from_env("/tmp/amateur_module_reorganization_result.json", temp_path)
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

    # --- Both modules exist (10 pts) ---
    both_exist = result.get('linear_exists', False) and result.get('fmvoice_exists', False)
    if both_exist:
        score += 10
        feedback_parts.append("Both Linear and FM_Voice modules exist")
    elif result.get('linear_exists'):
        score += 5
        feedback_parts.append("Linear module exists; FM_Voice module NOT FOUND")
    elif result.get('fmvoice_exists'):
        score += 5
        feedback_parts.append("FM_Voice module exists; Linear module NOT FOUND")
    else:
        feedback_parts.append("CRITICAL: Neither Linear nor FM_Voice module found")

    # --- Linear module satellites (30 pts total, 10 per satellite) ---
    linear_sats_found = []
    linear_sats_missing = []

    if result.get('linear_exists'):
        has_ao7 = result.get('linear_has_ao7', False)
        has_fo29 = result.get('linear_has_fo29', False)
        has_ao73 = result.get('linear_has_ao73', False)

        if has_ao7:
            score += 10
            linear_sats_found.append("AO-7 (7530)")
        else:
            linear_sats_missing.append("AO-7 (7530)")

        if has_fo29:
            score += 10
            linear_sats_found.append("FO-29 (24278)")
        else:
            linear_sats_missing.append("FO-29 (24278)")

        if has_ao73:
            score += 10
            linear_sats_found.append("FuncUBE-1/AO-73 (39444)")
        else:
            linear_sats_missing.append("FuncUBE-1/AO-73 (39444)")

        if linear_sats_found:
            feedback_parts.append(f"Linear module has: {', '.join(linear_sats_found)}")
        if linear_sats_missing:
            feedback_parts.append(f"Linear module MISSING: {', '.join(linear_sats_missing)}")
    else:
        feedback_parts.append("Linear module: cannot check satellites (module not found)")

    # --- FM_Voice module satellites (40 pts total, 10 per satellite) ---
    fmvoice_sats_found = []
    fmvoice_sats_missing = []

    if result.get('fmvoice_exists'):
        has_ao27 = result.get('fmvoice_has_ao27', False)
        has_so50 = result.get('fmvoice_has_so50', False)
        has_ao85 = result.get('fmvoice_has_ao85', False)
        has_ao95 = result.get('fmvoice_has_ao95', False)

        if has_ao27:
            score += 10
            fmvoice_sats_found.append("AO-27 (22825)")
        else:
            fmvoice_sats_missing.append("AO-27 (22825)")

        if has_so50:
            score += 10
            fmvoice_sats_found.append("SO-50 (27607)")
        else:
            fmvoice_sats_missing.append("SO-50 (27607)")

        if has_ao85:
            score += 10
            fmvoice_sats_found.append("AO-85 (40967)")
        else:
            fmvoice_sats_missing.append("AO-85 (40967)")

        if has_ao95:
            score += 10
            fmvoice_sats_found.append("AO-95 (43770)")
        else:
            fmvoice_sats_missing.append("AO-95 (43770)")

        if fmvoice_sats_found:
            feedback_parts.append(f"FM_Voice module has: {', '.join(fmvoice_sats_found)}")
        if fmvoice_sats_missing:
            feedback_parts.append(f"FM_Voice module MISSING: {', '.join(fmvoice_sats_missing)}")
    else:
        feedback_parts.append("FM_Voice module: cannot check satellites (module not found)")

    # --- Remote_RX ground station (20 pts) ---
    if result.get('remote_rx_exists'):
        lat_ok = _close_enough(result.get('remote_rx_lat', ''), metadata.get('remote_rx_lat', 40.7484), 0.1)
        lon_ok = _close_enough(result.get('remote_rx_lon', ''), metadata.get('remote_rx_lon', -74.0060), 0.1)
        alt_ok = _close_enough(result.get('remote_rx_alt', ''), metadata.get('remote_rx_alt', 10), 20)

        if lat_ok and lon_ok and alt_ok:
            score += 20
            feedback_parts.append("Remote_RX ground station: correct")
        elif lat_ok and lon_ok:
            score += 12
            feedback_parts.append(f"Remote_RX: coordinates OK but altitude off ({result.get('remote_rx_alt')}m, expected 10m)")
        else:
            score += 5
            feedback_parts.append(f"Remote_RX exists but coordinates wrong (lat={result.get('remote_rx_lat')}, lon={result.get('remote_rx_lon')})")
    else:
        feedback_parts.append("Remote_RX ground station: NOT FOUND (no .qth near 40.7N, 74.0W)")

    passed = score >= 70

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts),
        "subscores": {
            "both_modules_exist": both_exist,
            "linear_complete": result.get('linear_has_ao7') and result.get('linear_has_fo29') and result.get('linear_has_ao73'),
            "fmvoice_complete": result.get('fmvoice_has_ao27') and result.get('fmvoice_has_so50') and result.get('fmvoice_has_ao85') and result.get('fmvoice_has_ao95'),
            "remote_rx_station": result.get('remote_rx_exists'),
        }
    }
