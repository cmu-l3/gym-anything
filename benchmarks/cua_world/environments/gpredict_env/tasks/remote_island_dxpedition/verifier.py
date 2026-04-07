#!/usr/bin/env python3
"""
Verifier for remote_island_dxpedition task.

Verification Criteria (100 points, pass >= 70):
1. Sable Island QTH exists w/ correct lat/lon/alt (15 pts)
2. Halifax QTH exists w/ correct lat/lon/alt (15 pts)
3. DXpedition.mod contains all 5 required satellites (30 pts)
4. DXpedition.mod is bound to Sable Island QTH (15 pts)
5. DXpedition.mod visual layout is List-only (15 pts)
6. Amateur.mod successfully deleted (10 pts)
"""

import json
import os
import base64
import re
import tempfile
import logging

logger = logging.getLogger(__name__)


def _close_enough(value_str, expected_float, tolerance=0.1):
    """Check if a string-encoded float is within tolerance of expected."""
    try:
        val = float(value_str)
        return abs(val - expected_float) <= tolerance
    except (ValueError, TypeError):
        return False


def verify_remote_island_dxpedition(traj, env_info, task_info):
    """Verify the DXpedition configuration task."""
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env unavailable"}

    metadata = task_info.get('metadata', {})

    try:
        temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        temp_path = temp_file.name
        temp_file.close()

        try:
            copy_from_env("/tmp/remote_island_dxpedition_result.json", temp_path)
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

    # --- 1. Sable Island QTH (15 pts) ---
    sable = result.get('sable_qth', {})
    if sable.get('exists'):
        lat_ok = _close_enough(sable.get('lat', ''), metadata.get('sable_lat', 43.9333), 0.1)
        lon_ok = _close_enough(sable.get('lon', ''), metadata.get('sable_lon', -59.9167), 0.1)
        alt_ok = _close_enough(sable.get('alt', ''), metadata.get('sable_alt', 5), 10)

        if lat_ok and lon_ok and alt_ok:
            score += 15
            feedback_parts.append("Sable Island QTH: correct")
        elif lat_ok and lon_ok:
            score += 10
            feedback_parts.append("Sable Island QTH: coords OK, altitude off")
        else:
            score += 5
            feedback_parts.append("Sable Island QTH: exists but coords inaccurate")
    else:
        feedback_parts.append("Sable Island QTH: NOT FOUND")

    # --- 2. Halifax QTH (15 pts) ---
    halifax = result.get('halifax_qth', {})
    if halifax.get('exists'):
        lat_ok = _close_enough(halifax.get('lat', ''), metadata.get('halifax_lat', 44.6488), 0.1)
        lon_ok = _close_enough(halifax.get('lon', ''), metadata.get('halifax_lon', -63.5752), 0.1)
        alt_ok = _close_enough(halifax.get('alt', ''), metadata.get('halifax_alt', 10), 20)

        if lat_ok and lon_ok and alt_ok:
            score += 15
            feedback_parts.append("Halifax QTH: correct")
        elif lat_ok and lon_ok:
            score += 10
            feedback_parts.append("Halifax QTH: coords OK, altitude off")
        else:
            score += 5
            feedback_parts.append("Halifax QTH: exists but coords inaccurate")
    else:
        feedback_parts.append("Halifax QTH: NOT FOUND")

    # --- 3, 4, 5. DXpedition Module checks ---
    dx_mod = result.get('dx_mod', {})
    if dx_mod.get('exists'):
        content_b64 = dx_mod.get('content_b64', '')
        try:
            content = base64.b64decode(content_b64).decode('utf-8', errors='ignore')
        except:
            content = ""

        # Check Satellites (30 pts - 6 per sat)
        sats_line = ""
        for line in content.splitlines():
            if line.upper().startswith("SATELLITES="):
                sats_line = line
                break
        
        required_sats = [
            (25544, 'ISS'),
            (7530, 'AO-7'),
            (27607, 'SO-50'),
            (39444, 'AO-73'),
            (40967, 'AO-85')
        ]
        
        found_sats = []
        for norad, name in required_sats:
            if str(norad) in sats_line:
                score += 6
                found_sats.append(name)
                
        if len(found_sats) == 5:
            feedback_parts.append("DXpedition Module: All 5 satellites present")
        else:
            feedback_parts.append(f"DXpedition Module: {len(found_sats)}/5 satellites found")

        # Check QTH Binding (15 pts)
        qth_bound = False
        sable_filename = sable.get('filename', 'Sable_Island.qth')
        for line in content.splitlines():
            if line.upper().startswith("QTHFILE="):
                qth_val = line.split('=', 1)[1].strip()
                if sable_filename.lower() in qth_val.lower() or "sable" in qth_val.lower():
                    qth_bound = True
                break
        
        if qth_bound:
            score += 15
            feedback_parts.append("DXpedition Module: Correctly bound to Sable Island QTH")
        else:
            feedback_parts.append("DXpedition Module: NOT bound to Sable Island QTH")

        # Check Layout (15 pts)
        # Requirements for List-only: SHOWMAP=0 (or missing), SHOWPOLARPLOT=0 (or missing), SHOWEV=1 (list active)
        show_map = True
        show_polar = True
        show_list = False
        
        if re.search(r'SHOWMAP\s*=\s*0', content, re.IGNORECASE) or not re.search(r'SHOWMAP\s*=', content, re.IGNORECASE):
            show_map = False
        if re.search(r'SHOWPOLARPLOT\s*=\s*0', content, re.IGNORECASE) or not re.search(r'SHOWPOLARPLOT\s*=', content, re.IGNORECASE):
            show_polar = False
        if re.search(r'SHOWEV\s*=\s*1', content, re.IGNORECASE):
            show_list = True

        if not show_map and not show_polar and show_list:
            score += 15
            feedback_parts.append("DXpedition Module Layout: Correct (List-only)")
        elif not show_map and not show_polar:
            score += 10
            feedback_parts.append("DXpedition Module Layout: Map/Polar removed, but List view missing")
        else:
            feedback_parts.append("DXpedition Module Layout: Still showing Map or Polar plot")
            
    else:
        feedback_parts.append("DXpedition Module: NOT FOUND")

    # --- 6. Workspace Cleanup / Amateur.mod deleted (10 pts) ---
    if not result.get('amateur_mod_exists', True):
        score += 10
        feedback_parts.append("Amateur.mod: Successfully deleted")
    else:
        feedback_parts.append("Amateur.mod: Still exists (workspace not decluttered)")

    # Key criteria for pass: The DX Module must exist with at least some of the satellites
    passed = score >= 70 and dx_mod.get('exists', False) and len(found_sats) >= 3

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }