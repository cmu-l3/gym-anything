#!/usr/bin/env python3
"""
Verifier for andes_horizon_masking task.

Task:
  1. Create Santiago_UChile ground station (Lat -33.45, Lon -70.66, Alt 520m)
  2. Import horizon mask file from /home/ga/Documents/andes_mask.txt into the QTH
  3. Create Andes_EO module tracking 37849, 32958, 37214
  4. Bind module to Santiago_UChile ground station
  5. Configure Map track orbits to 4

Scoring (100 points, pass >= 70):
  - Santiago QTH exists with correct coordinates: 15 pts
  - Horizon mask imported (QTH contains [Horizon] with valid interpolated data): 25 pts
  - Andes_EO module exists and tracks all 3 satellites: 15 pts
  - Andes_EO module specifically bound to Santiago QTH: 20 pts
  - Multi-orbit ground track configured (TRACK_ORBITS=4): 25 pts
"""

import json
import os
import re
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


def verify_andes_horizon_masking(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env unavailable"}

    metadata = task_info.get('metadata', {})
    expected_lat = metadata.get('santiago_lat', -33.45)
    expected_lon = metadata.get('santiago_lon', -70.66)
    expected_alt = metadata.get('santiago_alt', 520)

    try:
        temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        temp_path = temp_file.name
        temp_file.close()

        try:
            copy_from_env("/tmp/andes_horizon_masking_result.json", temp_path)
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

    qth_content = result.get('santiago_qth_content', '')
    mod_content = result.get('andes_mod_content', '')

    # --- Criterion 1: Santiago QTH exists & coords correct (15 pts) ---
    if result.get('santiago_qth_exists') and qth_content:
        # Extract lat, lon, alt using regex
        lat_m = re.search(r'LAT=([-.\d]+)', qth_content, re.IGNORECASE)
        lon_m = re.search(r'LON=([-.\d]+)', qth_content, re.IGNORECASE)
        alt_m = re.search(r'ALT=([-.\d]+)', qth_content, re.IGNORECASE)

        lat_val = lat_m.group(1) if lat_m else None
        lon_val = lon_m.group(1) if lon_m else None
        alt_val = alt_m.group(1) if alt_m else None

        lat_ok = _close_enough(lat_val, expected_lat, 0.5)
        lon_ok = _close_enough(lon_val, expected_lon, 0.5)
        alt_ok = _close_enough(alt_val, expected_alt, 10.0)

        if lat_ok and lon_ok and alt_ok:
            score += 15
            feedback_parts.append("Santiago QTH coordinates correct")
        else:
            score += 5
            feedback_parts.append(f"Santiago QTH exists, but coordinates inaccurate (Lat:{lat_val}, Lon:{lon_val}, Alt:{alt_val})")
    else:
        feedback_parts.append("Santiago QTH NOT FOUND")

    # --- Criterion 2: Horizon Mask Imported (25 pts) ---
    if qth_content:
        # Check if the [Horizon] section exists and has elements mapping azimuth to elevation (e.g., "90=20")
        if '[Horizon]' in qth_content or '[horizon]' in qth_content.lower():
            # The agent imported the mask, GPredict writes out 360 lines like "0=5.0", "90=20.0"
            if re.search(r'90=20\.?0*', qth_content) or re.search(r'45=10\.?0*', qth_content):
                score += 25
                feedback_parts.append("Horizon terrain mask successfully imported")
            else:
                score += 15
                feedback_parts.append("Horizon section exists, but profile values don't match expected Andes mask")
        else:
            feedback_parts.append("Horizon terrain mask NOT imported")
    else:
        feedback_parts.append("Cannot verify horizon mask (QTH file missing)")

    # --- Criterion 3: Andes_EO Module & Satellites (15 pts) ---
    if result.get('andes_mod_exists') and mod_content:
        satellites_m = re.search(r'SATELLITES=([^|]+)', mod_content, re.IGNORECASE)
        sat_string = satellites_m.group(1) if satellites_m else ""

        has_37849 = "37849" in sat_string
        has_32958 = "32958" in sat_string
        has_37214 = "37214" in sat_string

        if has_37849 and has_32958 and has_37214:
            score += 15
            feedback_parts.append("Andes_EO module tracks all 3 target satellites")
        elif has_37849 or has_32958 or has_37214:
            score += 5
            feedback_parts.append("Andes_EO module tracks partial satellite list")
        else:
            feedback_parts.append("Andes_EO module missing target satellites")
    else:
        feedback_parts.append("Andes_EO module NOT FOUND")

    # --- Criterion 4: QTH Bound to Module (20 pts) ---
    if mod_content:
        qthfile_m = re.search(r'QTHFILE=([^|]+)', mod_content, re.IGNORECASE)
        qthfile_val = qthfile_m.group(1).lower() if qthfile_m else ""

        if "santiago" in qthfile_val:
            score += 20
            feedback_parts.append("Module successfully bound to Santiago QTH")
        else:
            feedback_parts.append(f"Module bound to wrong QTH (expected Santiago, found: {qthfile_val})")
    else:
        feedback_parts.append("Cannot verify module binding (Module file missing)")

    # --- Criterion 5: Multi-Orbit Configured (25 pts) ---
    if mod_content:
        # GPredict saves this as TRACK_ORBITS=4
        orbits_m = re.search(r'TRACK_ORBITS=([0-9]+)', mod_content, re.IGNORECASE)
        # Also check fallback ORBITS=4 just in case
        fallback_m = re.search(r'ORBITS=([0-9]+)', mod_content, re.IGNORECASE)
        
        orbit_val = orbits_m.group(1) if orbits_m else (fallback_m.group(1) if fallback_m else None)

        if orbit_val == "4":
            score += 25
            feedback_parts.append("Multi-orbit tracking configured to 4 orbits")
        elif orbit_val:
            feedback_parts.append(f"Multi-orbit tracking configured, but wrong value (found {orbit_val}, expected 4)")
        else:
            feedback_parts.append("Multi-orbit tracking NOT configured (default 1 orbit remaining)")
    else:
        feedback_parts.append("Cannot verify map orbits (Module file missing)")

    passed = score >= 70
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }